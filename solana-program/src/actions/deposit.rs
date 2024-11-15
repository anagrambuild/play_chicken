use anchor_lang::prelude::*;
use anchor_spl::{token_2022::TransferChecked, token_interface::{Mint, TokenAccount, TokenInterface}};
use crate::{error::ChickenError, state::{Pool, UserPosition}};

use super::{bps, update_pool_state,assert_pool_active};

#[derive(Accounts)]
#[instruction(amount: u64)]
pub struct Deposit<'info> {
    #[account(mut)]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
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
    #[account(
      init_if_needed,
      payer = payer,
      space = 8 + std::mem::size_of::<UserPosition>(),
      seeds = [
        b"user_position".as_ref(),
        pool.key().as_ref(),
        user.key().as_ref(),
      ],
      bump
    )]
    pub user_position: Account<'info, UserPosition>,
    pub collateral_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    pub system_program: Program<'info, System>,
}

pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
    let current_slot = Clock::get()?.slot;
    let pool = &mut ctx.accounts.pool;
    let token_account_amount = ctx.accounts.pool_collateral_token_account.amount;
    update_pool_state(pool, current_slot)?;
    assert_pool_active(pool)?;
    let user_position = &mut ctx.accounts.user_position;
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
    anchor_spl::token_interface::transfer_checked(
      CpiContext::new(
          ctx.accounts.token_program.to_account_info(),
          TransferChecked {
              from: ctx.accounts.user_collateral_token_account.to_account_info(),
              to: ctx.accounts.pool_collateral_token_account.to_account_info(),
              authority: ctx.accounts.user.to_account_info(),
              mint: ctx.accounts.collateral_mint.to_account_info(),
          }
      ),
      amount,
      ctx.accounts.collateral_mint.decimals,
    )?;
    
    pool.users += 1;
    let fee = bps(amount, pool.deposit_fee_bps)?;
    let collateral = bps(amount - fee, pool.collateral_bps)?;
    pool.fee_amount += fee;
    pool.collateral_amount += collateral;
    if user_position.deposit_time == 0 {
        user_position.deposit_time = current_slot;
    }
    user_position.owner = ctx.accounts.user.key();
    user_position.pool = pool.key();
    user_position.collateral_amount += collateral;
    user_position.deposit_amount += amount - fee - collateral;
    Ok(())
}