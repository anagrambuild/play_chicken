mod claim_fees;
mod deposit;
mod init;
mod remove_pool;
mod withdraw;

use crate::{
    error::ChickenError,
    state::{Pool, PoolState},
};
use anchor_lang::{error::ErrorCode, prelude::Result};

pub use claim_fees::*;
pub use deposit::*;
pub use init::*;
pub use remove_pool::*;
pub use withdraw::*;

#[inline(always)]
pub fn update_pool_state(pool: &mut Pool, current_slot: u64) -> Result<()> {
    if pool.state == PoolState::Removed {
        return Ok(());
    }
    if current_slot >= pool.start_time && current_slot <= pool.end_time {
        pool.state = PoolState::Started;
    }
    if current_slot > pool.end_time {
        pool.state = PoolState::Ended;
    }
    Ok(())
}

#[inline(always)]
pub fn assert_pool_active(pool: &Pool) -> std::result::Result<(), ChickenError> {
    match pool.state {
        PoolState::Started => Ok(()),
        PoolState::Ended => Err(ChickenError::PoolEnded),
        PoolState::Removed => Err(ChickenError::PoolRemoved),
        PoolState::Pending => Err(ChickenError::PoolPending),
    }
}

#[inline(always)]
pub fn assert_pool_withdrawable(pool: &Pool) -> std::result::Result<(), ChickenError> {
    match pool.state {
        PoolState::Started => Ok(()),
        PoolState::Ended => Ok(()),
        PoolState::Removed => Err(ChickenError::PoolRemoved),
        PoolState::Pending => Err(ChickenError::PoolPending),
    }
}

#[inline(always)]
pub fn bps(amount: u64, bps: u16) -> Result<u64> {
    Ok((amount as u128)
        .checked_mul(bps as u128)
        .ok_or(ErrorCode::InvalidNumericConversion)?
        .checked_div(10_000)
        .ok_or(ErrorCode::InvalidNumericConversion)? as u64)
}
