use anchor_lang::prelude::*;

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone, Copy, Default, Eq, PartialEq)]
pub enum PoolState {
    #[default]
    Pending = 0,
    Started = 1,
    Ended = 2,
    Removed = 3,
}

#[derive(Debug, AnchorSerialize, AnchorDeserialize, Clone, Copy, Default, Eq, PartialEq)]
pub enum PoolMode {
    #[default]
    LastOutWinner = 0,
    TimeBased = 1,
}

#[account]
#[derive(Debug, Default)]
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

#[account]
#[derive(Debug, Default)]
pub struct UserPosition {
    pub owner: Pubkey,
    pub pool: Pubkey,
    pub collateral_amount: u64,
    pub deposit_amount: u64,
    pub deposit_time: u64,
    pub withdrawn: bool,
}
