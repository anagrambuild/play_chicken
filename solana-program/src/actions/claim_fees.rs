use super::update_pool_state;
use crate::{
    error::ChickenError,
    state::{Pool, PoolState},
};
use anchor_lang::prelude::*;
use anchor_spl::{
    token_2022::TransferChecked,
    token_interface::{Mint, TokenAccount, TokenInterface},
};
use anchor_lang::solana_program::program_memory::sol_memcpy;

#[derive(Accounts)]
pub struct ClaimFees<'info> {
    #[account(mut)]
    pub pool: Account<'info, Pool>,
    #[account(mut,
        associated_token::mint = pool.collateral_mint,
        associated_token::authority = pool,
        associated_token::token_program = token_program
    )]
    pub pool_collateral_token_account: InterfaceAccount<'info, TokenAccount>,
    #[account(mut,
        token::mint = pool.collateral_mint,
        token::authority = admin,
        token::token_program = token_program
    )]
    pub admin_token_account: InterfaceAccount<'info, TokenAccount>,
    pub admin: Signer<'info>,
    pub admin_record: UncheckedAccount<'info>,
    pub collateral_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
}

pub fn claim_fees(ctx: Context<ClaimFees>) -> Result<()> {
    let get_admin_record: &[u8] = &ctx.accounts.admin_record.data.borrow();
    if get_admin_record != ctx.accounts.admin.key.as_ref() {
        return err!(ChickenError::Unauthorized);
    }
    let current_slot = Clock::get()?.slot;
    let pool_info = ctx.accounts.pool.to_account_info();
    let pool = &mut ctx.accounts.pool;
    update_pool_state(pool, current_slot)?;
    if pool.state != PoolState::Ended {
        return err!(ChickenError::PoolEnded);
    }
    let fee_amount = pool.fee_amount;
    pool.fee_amount = 0;
    anchor_spl::token_interface::transfer_checked(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            TransferChecked {
                from: ctx.accounts.pool_collateral_token_account.to_account_info(),
                to: ctx.accounts.admin_token_account.to_account_info(),
                authority: pool_info,
                mint: ctx.accounts.collateral_mint.to_account_info(),
            },
            &[&[b"pool".as_ref(), pool.pool_id.as_ref(), &[pool.bump]]],
        ),
        fee_amount,
        ctx.accounts.collateral_mint.decimals,
    )?;

    Ok(())
}

#[derive(Accounts)]
pub struct InitializeAdmin<'info> {
    #[account(
      init,
      payer = admin,
      space = 40,
      seeds = [
        b"admin".as_ref(),
      ],
      bump
    )]
    /// CHECK: Admin account
    pub admin_record: UncheckedAccount<'info>,  
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

pub fn initialize_admin(ctx: Context<InitializeAdmin>) -> Result<()> {
    let admin_record = &mut ctx.accounts.admin_record.to_account_info();
    sol_memcpy(
        &mut admin_record.data.borrow_mut(),
        ctx.accounts.admin.key.as_ref(),
        32,
    );
    Ok(())
}

#[derive(Accounts)]
pub struct ChangeAdmin<'info> {
    #[account(
      mut,
      seeds = [
        b"admin".as_ref(),
      ],
      bump
    )]
    /// CHECK: Admin account
    pub admin_record: UncheckedAccount<'info>,  
    #[account(mut)]
    pub admin: Signer<'info>,
    pub new_admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

pub fn change_admin(ctx: Context<ChangeAdmin>) -> Result<()> {
    let get_admin_record: &[u8] = &ctx.accounts.admin_record.data.borrow();
    if get_admin_record != ctx.accounts.admin.key.as_ref() {
        return err!(ChickenError::Unauthorized);
    }
    let admin_record = &mut ctx.accounts.admin_record.to_account_info();
    sol_memcpy(
        &mut admin_record.data.borrow_mut(),
        ctx.accounts.new_admin.key.as_ref(),
        32,
    );
    Ok(())
}