use anchor_lang::prelude::*;
use anchor_spl::token_interface::{Mint, TokenAccount, TokenInterface};

use crate::{
    state::{Pool, PoolMode, PoolState},
    DEPOSIT_FEE_BPS, WITHDRAW_FEE_BPS,
};

#[derive(Accounts)]
#[instruction(args: InitializePoolArgs)]
pub struct InitializePool<'info> {
    #[account(
        init,
        payer = creator,
        space = 8 + std::mem::size_of::<Pool>(),
        seeds = [
            b"pool".as_ref(),
            args.pool_id.as_ref(),
            creator.key().as_ref(),
        ],
        bump
    )]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub creator: Signer<'info>,
    pub pool_collateral_mint: InterfaceAccount<'info, Mint>,
    #[account(mut, associated_token::mint = pool_collateral_mint,
      associated_token::authority = pool,
      associated_token::token_program = token_program
    )]
    pub pool_collateral_token_account: InterfaceAccount<'info, TokenAccount>,
    pub token_program: Interface<'info, TokenInterface>,
    pub system_program: Program<'info, System>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct InitializePoolArgs {
    pub pool_id: [u8; 16],
    pub pool_mode: PoolMode,
    pub collateral_bps: u16,
    pub start_time: u64,
    pub end_time: u64,
    pub minimum_deposit: u64,
    pub total_deposit_limit: Option<u64>,
    pub max_deposit: Option<u64>,
}

pub fn initialize_pool(ctx: Context<InitializePool>, args: InitializePoolArgs) -> Result<()> {
    let pool = &mut ctx.accounts.pool;
    pool.state = PoolState::Pending;
    pool.creator = ctx.accounts.creator.key();
    pool.bump = ctx.bumps.pool;
    pool.deposit_fee_bps = DEPOSIT_FEE_BPS;
    pool.withdraw_fee_bps = WITHDRAW_FEE_BPS;
    pool.collateral_bps = args.collateral_bps;
    pool.mode = args.pool_mode;
    pool.start_time = args.start_time;
    pool.end_time = args.end_time;
    pool.min_deposit = args.minimum_deposit;
    pool.pool_id = args.pool_id;
    pool.authority = ctx.accounts.creator.key();
    pool.collateral_mint = ctx.accounts.pool_collateral_mint.key();
    pool.withdrawn = 0;
    pool.total_deposit_limit = args.total_deposit_limit;
    pool.max_deposit = args.max_deposit;
    Ok(())
}
