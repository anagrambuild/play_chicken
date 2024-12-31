use crate::{
    accounts::Context,
    assertions::{check_self_pda, check_signer},
    state::PoolState,
};
use borsh::{BorshDeserialize, BorshSerialize};
use pinocchio::{
    instruction::{Seed, Signer},
    memory::sol_memset,
    msg,
    sysvars::{clock::Clock, Sysvar},
    ProgramResult,
};
use pinocchio_token::{instructions::Transfer, state::TokenAccount};

use super::{assert_pool_withdrawable, bps, update_pool_state};
use crate::{
    accounts::WithdrawAccounts,
    error::ChickenError,
    state::{Pool, PoolMode, UserPosition},
};

pub fn withdraw(ctx: Context<WithdrawAccounts>) -> ProgramResult {
    let current_slot = Clock::get()?.slot;
    check_signer(ctx.accounts.user, ChickenError::Unauthorized)?;
    let mut pd = unsafe { ctx.accounts.pool.borrow_mut_data_unchecked() };
    let mut pool = Pool::try_from_slice(pd).map_err(|e| {
        msg!("DeserializationError: {:?}", e);
        ChickenError::DeserializationError
    })?;
    let upd = unsafe { ctx.accounts.user_position.borrow_mut_data_unchecked() };
    let user_position =
        UserPosition::try_from_slice(upd).map_err(|_| ChickenError::DeserializationError)?;
    check_self_pda(
        &[
            b"user_position".as_ref(),
            ctx.accounts.pool.key().as_ref(),
            ctx.accounts.user.key().as_ref(),
            &[user_position.bump],
        ],
        ctx.accounts.user_position.key(),
        ChickenError::InvalidPoolPositionAddress,
    )?;
    update_pool_state(&mut pool, current_slot)?;
    assert_pool_withdrawable(&pool)?;
    let pool_ata = unsafe {
        TokenAccount::from_account_info_unchecked(ctx.accounts.pool_collateral_token_account)?
    };
    let cm_key = ctx.accounts.colateral_mint.key();
    if pool_ata.mint() != cm_key {
        return Err(ChickenError::InvalidTokenAccount.into());
    }
    if pool_ata.owner() != ctx.accounts.pool.key() {
        return Err(ChickenError::InvalidTokenAccount.into());
    }
    if cm_key != &pool.collateral_mint {
        return Err(ChickenError::InvalidMint.into());
    }
    let total_deposits = pool_ata.amount() - pool.fee_amount - pool.collateral_amount;
    let return_amount = match pool.mode {
        PoolMode::LastOutWinner => {
            if pool.users == 1 {
                (
                    user_position.deposit_amount + pool.collateral_amount,
                    pool.collateral_amount,
                )
            } else {
                (user_position.deposit_amount, 0u64)
            }
        }
        PoolMode::TimeBased => {
            let total_slots = pool
                .end_time
                .checked_sub(pool.start_time)
                .unwrap_or_default();
            let slots_passed = current_slot
                .checked_sub(pool.start_time)
                .unwrap_or_default();
            msg!("total slots {}", total_slots);
            msg!("slots passed {}", slots_passed);

            // Calculate time in pool as percentage (0-100)
            let time_in_pool = ((user_position
                .deposit_time
                .checked_sub(pool.start_time)
                .unwrap_or_default())
            .checked_add(slots_passed)
            .unwrap_or_default())
            .checked_mul(100)
            .and_then(|val| val.checked_div(total_slots))
            .unwrap_or_default();
            msg!("time in pool {}", time_in_pool);

            // Cubic penalty: (time_in_pool/100)^3 * 100 to get percentage
            let penalty_percentage = time_in_pool
                .checked_pow(3)
                .and_then(|val| val.checked_div(10000)) // Divide by 100^2 to convert back to percentage
                .unwrap_or_default();
            let penalty_percentage = 100u64.checked_sub(penalty_percentage).unwrap_or_default();
            msg!("penalty percentage {}", penalty_percentage);

            // Apply penalty percentage to collateral
            let collateral_penalty = user_position
                .collateral_amount
                .checked_mul(penalty_percentage)
                .and_then(|val| val.checked_div(100))
                .unwrap_or_default();
            msg!("collateral penalty {}", collateral_penalty);

            let collateral_refund = user_position
                .collateral_amount
                .checked_sub(collateral_penalty)
                .unwrap_or_default();
            msg!("collateral refund {}", collateral_refund);

            // Calculate user's share
            let user_deposit_percentage = user_position
                .deposit_amount
                .checked_mul(100)
                .and_then(|val| val.checked_div(total_deposits))
                .unwrap_or_default();

            let pool_collateral_amount = pool
                .collateral_amount
                .checked_sub(collateral_refund)
                .unwrap_or_default();

            let user_collateral_amount = pool_collateral_amount
                .checked_mul(user_deposit_percentage)
                .and_then(|val| val.checked_div(100))
                .unwrap_or_default();

            // Quadratic reward: (time_in_pool/100)^2 * 100 to get percentage
            let reward_percentage = time_in_pool
                .checked_pow(2)
                .and_then(|val| val.checked_div(100)) // Divide by 100 to convert back to percentage
                .unwrap_or_default();
            msg!("reward percentage {}", reward_percentage);

            let rewards = user_collateral_amount
                .checked_mul(reward_percentage)
                .and_then(|val| val.checked_div(100))
                .unwrap_or_default();
            msg!("rewards {}", rewards);

            (
                user_position.deposit_amount + collateral_refund + rewards,
                collateral_refund + rewards,
            )
        }
    };
    let fee = bps(return_amount.0, pool.withdraw_fee_bps)?;
    msg!("fee {}", fee);
    msg!("final amount less fee {}", return_amount.0);
    msg!("final amount {}", return_amount.0 - fee);
    let final_amount = return_amount.0 - fee;
    pool.withdrawn += final_amount;
    pool.users -= 1;
    pool.fee_amount += fee;
    pool.collateral_amount -= return_amount.1;
    Transfer {
        from: ctx.accounts.pool_collateral_token_account,
        to: ctx.accounts.user_collateral_token_account,
        authority: ctx.accounts.pool,
        amount: final_amount,
    }
    .invoke_signed(&[Signer::from(&[
        Seed::from(b"pool".as_ref()),
        Seed::from(pool.pool_id.as_ref()),
        Seed::from(pool.creator.as_ref()),
        Seed::from(&[pool.bump]),
    ])])?;
    unsafe {
        let up_lamports = ctx.accounts.user_position.lamports();
        *ctx.accounts.user_position.borrow_mut_lamports_unchecked() -= up_lamports;
        *ctx.accounts.user.borrow_mut_lamports_unchecked() += up_lamports;
    }
    if pool.users == 0 {
        pool.state = PoolState::Ended;
    }
    unsafe {
        sol_memset(upd, 0, ctx.accounts.user_position.data_len());
    }
    pool.serialize(&mut &mut pd).map_err(|e| {
        msg!("{}", e);
        ChickenError::SerializationError
    })?;

    Ok(())
}
