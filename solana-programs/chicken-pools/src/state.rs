use borsh::{BorshDeserialize, BorshSerialize};
use pinocchio::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, PartialEq, Debug, Clone, Copy)]
pub enum PoolState {
    Pending,
    Started,
    Ended,
    Removed,
}

#[derive(BorshSerialize, BorshDeserialize, PartialEq, Debug, Clone, Copy)]
pub enum PoolMode {
    LastOutWinner,
    TimeBased,
}

#[derive(Debug, BorshSerialize, BorshDeserialize)]
pub struct Pool {
    pub state: PoolState,
    pub bump: u8,
    pub creator: Pubkey,
    pub deposit_fee_bps: u16,
    pub withdraw_fee_bps: u16,
    pub collateral_bps: u16,
    pub collateral_amount: u64,
    pub fee_amount: u64,
    pub mode: PoolMode,
    pub start_time: u64,
    pub end_time: u64,
    pub min_deposit: u64,
    pub users: u32,
    pub withdrawn: u64,
    pub pool_id: [u8; 16],
    pub authority: Pubkey,
    pub collateral_mint: Pubkey,
    pub max_deposit: Option<u64>,
    pub total_deposit_limit: Option<u64>,
}

#[derive(Debug, Default, BorshSerialize, BorshDeserialize)]
pub struct UserPosition {
    pub bump: u8,
    pub owner: Pubkey,
    pub pool: Pubkey,
    pub collateral_amount: u64,
    pub deposit_amount: u64,
    pub deposit_time: u64,
    pub withdrawn: bool,
}

impl UserPosition {
    pub fn new(owner: Pubkey, pool: Pubkey, bump: u8) -> Self {
        Self {
            owner,
            pool,
            bump,
            ..Default::default()
        }
    }
}
