use borsh::{BorshDeserialize, BorshSerialize};
use pinocchio::{
    instruction::{Seed, Signer},
    msg,
    sysvars::{clock::Clock, rent::Rent, Sysvar},
    ProgramResult,
};
use pinocchio_system::instructions::CreateAccount;
use pinocchio_token::{
    instructions::Transfer,
    state::{Mint, TokenAccount},
};

use crate::{
    accounts::{Context, DepositAccounts},
    assertions::{account_empty, check_self_pda, check_signer, find_self_pda},
    error::ChickenError,
    state::{Pool, UserPosition},
};

use super::{assert_pool_active, bps, update_pool_state};

pub fn deposit(ctx: Context<DepositAccounts>, amount: u64) -> ProgramResult {
    let current_slot = Clock::get()?.slot;
    let pool_account = ctx.accounts.pool;
    check_signer(ctx.accounts.user, ChickenError::Unauthorized)?;
    let mut pd = unsafe { pool_account.borrow_mut_data_unchecked() };
    let mut pool = Pool::try_from_slice(pd).map_err(|e| {
        msg!("DeserializationError: {:?}", e);
        ChickenError::DeserializationError
    })?;
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
    check_self_pda(
        &[
            b"pool".as_ref(),
            pool.pool_id.as_ref(),
            pool.creator.as_ref(),
            &[pool.bump],
        ],
        ctx.accounts.pool.key(),
        ChickenError::InvalidPoolAddress,
    )?;
    let fee = bps(amount, pool.deposit_fee_bps)?;
    let collateral = bps(amount - fee, pool.collateral_bps)?;
    pool.users += 1;
    pool.collateral_amount += collateral;
    pool.fee_amount += fee;
    let mut user_position = if account_empty(ctx.accounts.user_position) {
        let bump = find_self_pda(
            &[
                b"user_position".as_ref(),
                ctx.accounts.pool.key().as_ref(),
                ctx.accounts.user.key().as_ref(),
            ],
            ctx.accounts.user_position.key(),
            ChickenError::InvalidPoolAddress,
        )?;
        let lamports_needed = Rent::get()?.minimum_balance(90);
        CreateAccount {
            from: ctx.accounts.payer,
            to: ctx.accounts.user_position,
            lamports: lamports_needed,
            space: 90,
            owner: &crate::ID,
        }
        .invoke_signed(&[Signer::from(&[
            Seed::from(b"user_position".as_ref()),
            Seed::from(ctx.accounts.pool.key().as_ref()),
            Seed::from(ctx.accounts.user.key().as_ref()),
            Seed::from(&[bump]),
        ])])?;
        UserPosition::new(*ctx.accounts.user.key(), *ctx.accounts.pool.key(), bump)
    } else {
        let upd = unsafe { ctx.accounts.user_position.borrow_mut_data_unchecked() };
        let up =
            UserPosition::try_from_slice(upd).map_err(|_| ChickenError::DeserializationError)?;
        check_self_pda(
            &[
                b"user_position".as_ref(),
                ctx.accounts.pool.key().as_ref(),
                ctx.accounts.user.key().as_ref(),
                &[up.bump],
            ],
            ctx.accounts.user_position.key(),
            ChickenError::InvalidPoolPositionAddress,
        )?;
        up
    };
    if user_position.deposit_time == 0 {
        user_position.deposit_time = current_slot;
    }
    user_position.collateral_amount += collateral;
    user_position.deposit_amount += amount - fee - collateral;
    let token_account_amount = pool_ata.amount();
    update_pool_state(&mut pool, current_slot)?;
    assert_pool_active(&pool)?;
    if let Some(tdl) = pool.total_deposit_limit {
        if token_account_amount + amount > tdl {
            return Err(ChickenError::PoolDepositLimitExceeded.into());
        }
    }
    if let Some(deposit_limit) = pool.max_deposit {
        if user_position.deposit_amount + amount > deposit_limit {
            return Err(ChickenError::UserDepositLimitExceeded.into());
        }
    }
    Transfer {
        from: ctx.accounts.user_collateral_token_account,
        to: ctx.accounts.pool_collateral_token_account,
        authority: ctx.accounts.user,
        amount,
    }
    .invoke()?;
    let mut upd = unsafe { ctx.accounts.user_position.borrow_mut_data_unchecked() };
    user_position.serialize(&mut &mut upd).map_err(|e| {
        msg!("{}", e);
        ChickenError::SerializationError
    })?;
    pool.serialize(&mut &mut pd).map_err(|e| {
        msg!("{}", e);
        ChickenError::SerializationError
    })?;
    Ok(())
}
