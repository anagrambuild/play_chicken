use anchor_lang::prelude::*;

#[error_code]
#[derive(PartialEq, Eq)]
pub enum ChickenError {
    #[msg("Pool is Pending")]
    PoolPending,
    #[msg("Pool has Ended")]
    PoolEnded,
    #[msg("Pool is Removed")]
    PoolRemoved,
    #[msg("User Deposit limit exceeded")]
    UserDepositLimitExceeded,
    #[msg("Pool Deposit limit exceeded")]
    PoolDepositLimitExceeded,
    #[msg("Pool is not Ended")]
    PoolNotEnded,
    #[msg("Unauthorized")]
    Unauthorized,
}