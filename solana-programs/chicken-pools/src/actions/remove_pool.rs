use crate::state::*;
use anchor_lang::prelude::*;

#[derive(Accounts)]
pub struct RemovePool<'info> {
    #[account(
        mut,
        seeds = [
            b"pool".as_ref(),
            pool.pool_id.as_ref(),
            creator.key().as_ref()
        ],
        bump = pool.bump,
        constraint = pool.state == PoolState::Ended,
        constraint = pool.users == 0,
        constraint = pool.collateral_amount == 0,
        constraint = pool.fee_amount == 0,
        realloc = 1,
        realloc::payer = payer,
        realloc::zero = false,
    )]
    pub pool: Account<'info, Pool>,
    #[account(mut)]
    pub creator: Signer<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    system_program: Program<'info, System>,
}

pub fn remove_pool(ctx: Context<RemovePool>) -> Result<()> {
    let pool = &mut ctx.accounts.pool;

    let current_minimum_balance = Rent::get()?.minimum_balance(1);
    let previous_minimum_balance = Rent::get()?.minimum_balance(std::mem::size_of::<Pool>());
    let rent_to_return = previous_minimum_balance.saturating_sub(current_minimum_balance);

    // Transfer rent back to authority
    if rent_to_return > 0 {
        **pool.to_account_info().try_borrow_mut_lamports()? = current_minimum_balance;
        **ctx
            .accounts
            .payer
            .to_account_info()
            .try_borrow_mut_lamports()? = ctx
            .accounts
            .payer
            .to_account_info()
            .lamports()
            .checked_add(rent_to_return)
            .unwrap();
    }

    pool.state = PoolState::Removed;
    Ok(())
}
