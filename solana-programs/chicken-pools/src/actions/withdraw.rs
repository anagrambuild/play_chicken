use super::{assert_pool_active, assert_pool_withdrawable, bps, update_pool_state};
use crate::{
    error::ChickenError,
    state::{Pool, PoolMode, PoolState, UserPosition},
};
use anchor_lang::prelude::*;
use anchor_spl::{
    token_2022::TransferChecked,
    token_interface::{Mint, TokenAccount, TokenInterface},
};

#[derive(Accounts)]
pub struct Withdraw<'info> {
    #[account(mut)]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut,
        associated_token::mint = pool.collateral_mint,
        associated_token::authority = pool,
        associated_token::token_program = token_program
    )]
    pub pool_collateral_token_account: InterfaceAccount<'info, TokenAccount>,
    #[account(mut,
        token::mint = pool.collateral_mint,
        token::authority = user,
        token::token_program = token_program
    )]
    pub user_collateral_token_account: InterfaceAccount<'info, TokenAccount>,
    #[account(mut,
        seeds = [
            b"user_position".as_ref(),
            pool.key().as_ref(),
            user.key().as_ref(),
        ],
        bump,
        constraint = user_position.owner == user.key(),
        constraint = user_position.pool == pool.key(),
        close = payer
    )]
    pub user_position: Account<'info, UserPosition>,
    pub collateral_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    pub system_program: Program<'info, System>,
}

pub fn withdraw(ctx: Context<Withdraw>) -> Result<()> {
    let current_slot = Clock::get()?.slot;
    let pool_info = ctx.accounts.pool.to_account_info();
    let pool = &mut ctx.accounts.pool;
    update_pool_state(pool, current_slot)?;
    assert_pool_withdrawable(pool)?;

    let total_deposits = ctx.accounts.pool_collateral_token_account.amount
        - pool.fee_amount
        - pool.collateral_amount;

    let user_position = &mut ctx.accounts.user_position;

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
            let total_slots = pool.end_time - pool.start_time;
            let slots_passed = current_slot - pool.start_time;

            let time_in_pool =
                (user_position.deposit_time - pool.start_time - slots_passed) / total_slots;
            let curve = time_in_pool ^ 3;
            let collateral_refund =
                user_position.collateral_amount - (user_position.collateral_amount * curve);
            let user_deposit_percentage = user_position.deposit_amount / total_deposits;
            let pool_collateral_amount = pool.collateral_amount - collateral_refund;
            let user_collateral_amount = pool_collateral_amount * user_deposit_percentage;
            let reward_curve = time_in_pool ^ 2;
            let rewards = user_collateral_amount - (user_collateral_amount * reward_curve);
            (
                user_position.deposit_amount + collateral_refund + rewards,
                collateral_refund + rewards,
            )
        }
    };

    let fee = bps(return_amount.0, pool.withdraw_fee_bps)?;
    let final_amount = return_amount.0 - fee;
    pool.withdrawn += final_amount;
    pool.users -= 1;
    pool.fee_amount += fee;
    pool.collateral_amount -= return_amount.1;
    pool.withdrawn += return_amount.0 - return_amount.1;
    anchor_spl::token_interface::transfer_checked(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            TransferChecked {      
                from: ctx.accounts.pool_collateral_token_account.to_account_info(),
                to: ctx.accounts.user_collateral_token_account.to_account_info(),
                authority: pool_info,
                mint: ctx.accounts.collateral_mint.to_account_info(),
            },
            &[&[
                b"pool".as_ref(),
                pool.pool_id.as_ref(),
                pool.creator.as_ref(),
                &[pool.bump],
            ]],
        ),
        final_amount,
        ctx.accounts.collateral_mint.decimals,
    )?;

    Ok(())
}
