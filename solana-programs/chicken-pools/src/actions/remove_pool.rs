use borsh::BorshDeserialize;
use pinocchio::{
    memory::sol_memset, msg, sysvars::{rent::Rent, Sysvar}, ProgramResult
};

use crate::{
    accounts::RemovePoolAccounts, assertions::{check_self_pda, check_signer}, error::ChickenError, state::*, Context,
};


pub fn remove_pool(ctx: Context<RemovePoolAccounts>) -> ProgramResult {
    let current_minimum_balance = Rent::get()?.minimum_balance(1);
    let previous_minimum_balance = Rent::get()?.minimum_balance(std::mem::size_of::<Pool>());
    ctx.accounts.pool.realloc(1, false)?;
    let rent_to_return = previous_minimum_balance.saturating_sub(current_minimum_balance);
    check_signer(ctx.accounts.creator, ChickenError::Unauthorized)?;
    let pd = unsafe { ctx.accounts.pool.borrow_mut_data_unchecked() };
    let pool = Pool::try_from_slice(pd).map_err(|_| ChickenError::DeserializationError)?;
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
    if pool.state != PoolState::Ended {
        return Err(ChickenError::PoolEnded.into());
    }
    if pool.users != 0 {
        return Err(ChickenError::PoolNotEmpty.into());
    }
    if pool.fee_amount != 0 {
        return Err(ChickenError::PoolNotEmpty.into());
    }
    // Transfer rent back to authority
    if rent_to_return > 0 {
        unsafe {
            *ctx.accounts.pool.borrow_mut_lamports_unchecked() = current_minimum_balance;
            *ctx.accounts.payer.borrow_mut_lamports_unchecked() += rent_to_return;
        }
    }
    unsafe {
        sol_memset(pd, PoolState::Removed as u8, ctx.accounts.pool.data_len());
    }
    Ok(())
}
