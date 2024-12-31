use pinocchio::{msg, program_error::ProgramError};
use thiserror::Error;

#[derive(PartialEq, Eq, Debug, Clone, Error)]
pub enum ChickenError {
    #[error("Invalid Numeric Conversion")]
    InvalidNumericConversion,
    #[error("Invalid Mint")]
    InvalidMint,
    #[error("Invalid Token Account")]
    InvalidTokenAccount,
    #[error("Invalid Instruction Data")]
    InvalidInstructionData,
    #[error("Pool Not Started")]
    PoolNotStarted,
    #[error("Pool Not Ended")]
    PoolNotEnded,
    #[error("Pool Removed")]
    PoolPending,
    #[error("Pool Ended")]
    PoolEnded,
    #[error("Pool Removed")]
    PoolRemoved,
    #[error("Pool Not Found")]
    PoolNotFound,
    #[error("Deposit Fees Exceeded")]
    UserDepositLimitExceeded,
    #[error("Pool Deposit limit exceeded")]
    PoolDepositLimitExceeded,
    #[error("Unauthorized")]
    Unauthorized,
    #[error("Pool Must Be Empty")]
    PoolMustBeEmpty,
    #[error("Invalid Pool Address")]
    InvalidPoolAddress,
    #[error("Invalid Pool Position Address")]
    InvalidPoolPositionAddress,
    #[error("Serialization Error")]
    SerializationError,
    #[error("Deserialization Error")]
    DeserializationError,
    #[error("Pool Not Empty")]
    PoolNotEmpty,
    #[error("Invalid Admin Record Address")]
    InvalidAdminRecordAddress,
}

impl From<ChickenError> for ProgramError {
    fn from(e: ChickenError) -> Self {
        msg!("ChickenError: {:?}", e);
        ProgramError::Custom(e as u32)
    }
}
