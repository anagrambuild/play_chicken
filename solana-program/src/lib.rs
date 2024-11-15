use actions::*;
use anchor_lang::prelude::*;
pub mod error;

pub mod actions;
pub mod state;

pub const DEPOSIT_FEE_BPS: u16 = 10;
pub const WITHDRAW_FEE_BPS: u16 = 10;

declare_id!("chknZh1FSSbASjrsFxTVPphCLQqeENFJJ2yTofyk3kB");

#[program]
pub mod chicken_pool {
    use super::*;

    pub fn initialize_pool(ctx: Context<InitializePool>, args: InitializePoolArgs) -> Result<()> {
        actions::initialize_pool(ctx, args)
    }

    pub fn deposit(ctx: Context<Deposit>, amount: u64) -> Result<()> {
        actions::deposit(ctx, amount)
    }

    pub fn withdraw(ctx: Context<Withdraw>) -> Result<()> {
        actions::withdraw(ctx)
    }

    pub fn remove_pool(ctx: Context<RemovePool>) -> Result<()> {
        actions::remove_pool(ctx)
    }

    pub fn claim_fees(ctx: Context<ClaimFees>) -> Result<()> {
        actions::claim_fees(ctx)
    }

    pub fn initialize_admin(ctx: Context<InitializeAdmin>) -> Result<()> {
        actions::initialize_admin(ctx)
    }

    pub fn change_admin(ctx: Context<ChangeAdmin>) -> Result<()> {
        actions::change_admin(ctx)
    }
}
