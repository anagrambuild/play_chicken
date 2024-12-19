mod init;
mod deposit;
mod remove_pool;
mod withdraw;
mod claim_fees;
pub use init::*;
pub use deposit::*;
pub use remove_pool::*;
pub use withdraw::*;
pub use claim_fees::*;
use crate::{
    error::ChickenError,
    state::{Pool, PoolState},
};

#[inline(always)]
pub fn update_pool_state(pool: &mut Pool, current_slot: u64) -> Result<(), ChickenError> {
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
pub fn bps(amount: u64, bps: u16) -> Result<u64, ChickenError> {
    Ok((amount as u128)
        .checked_mul(bps as u128)
        .ok_or(ChickenError::InvalidNumericConversion)?
        .checked_div(10_000)
        .ok_or(ChickenError::InvalidNumericConversion)? as u64)
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bps() {
        assert_eq!(bps(999, 10).unwrap(), 1);
        assert_eq!(bps(100, 100).unwrap(), 1);
        assert_eq!(bps(100, 500).unwrap(), 5);
        assert_eq!(bps(100, 1000).unwrap(), 10);
        assert_eq!(bps(100, 0).unwrap(), 0);
    }
}   