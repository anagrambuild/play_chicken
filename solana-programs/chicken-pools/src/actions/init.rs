use crate::accounts::Context;
use crate::assertions::*;
use crate::error::ChickenError;
use crate::{
    accounts::InitializePoolAccounts,
    state::{Pool, PoolMode, PoolState},
    DEPOSIT_FEE_BPS, WITHDRAW_FEE_BPS,
};
use borsh::{BorshDeserialize, BorshSerialize};
use pinocchio::instruction::{Seed, Signer};
use pinocchio::memory::sol_memmove;
use pinocchio::sysvars::rent::Rent;
use pinocchio::sysvars::Sysvar;
use pinocchio::ProgramResult;
use pinocchio_system::instructions::CreateAccount;
use pinocchio_token::state::{Mint, TokenAccount};

#[derive(BorshSerialize, BorshDeserialize, Clone)]
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

pub fn initialize_pool(
    ctx: Context<InitializePoolAccounts>,
    args: InitializePoolArgs,
) -> ProgramResult {
    let pool = ctx.accounts.pool;
    check_zero_balance(pool, ChickenError::PoolMustBeEmpty)?;
    unsafe {
        Mint::from_account_info_unchecked(ctx.accounts.pool_collateral_mint)
            .map_err(|_| ChickenError::InvalidMint)?
    };
    let ta = unsafe {
        TokenAccount::from_account_info_unchecked(ctx.accounts.pool_collateral_token_account)
            .map_err(|_| ChickenError::InvalidTokenAccount)?
    };
    if ta.mint() != ctx.accounts.pool_collateral_mint.key() {
        return Err(ChickenError::InvalidTokenAccount.into());
    }
    let bump = find_self_pda(
        &[
            b"pool".as_ref(),
            args.pool_id.as_ref(),
            ctx.accounts.creator.key().as_ref(),
        ],
        ctx.accounts.pool.key(),
        ChickenError::InvalidPoolAddress,
    )?;
    let pool = Pool {
        state: PoolState::Pending,
        bump,
        creator: *ctx.accounts.creator.key(),
        deposit_fee_bps: DEPOSIT_FEE_BPS,
        withdraw_fee_bps: WITHDRAW_FEE_BPS,
        collateral_bps: args.collateral_bps,
        collateral_amount: 0,
        fee_amount: 0,
        mode: args.pool_mode,
        start_time: args.start_time,
        end_time: args.end_time,
        min_deposit: args.minimum_deposit,
        users: 0,
        withdrawn: 0,
        pool_id: args.pool_id,
        authority: *ctx.accounts.creator.key(),
        collateral_mint: *ctx.accounts.pool_collateral_mint.key(),
        max_deposit: args.max_deposit,
        total_deposit_limit: args.total_deposit_limit,
    };
    let mut init_vec = Vec::with_capacity(208);
    pool.serialize(&mut init_vec)
        .map_err(|_| ChickenError::SerializationError)?;
    let space_needed = init_vec.len();
    let lamports_needed = Rent::get()?.minimum_balance(space_needed);
    CreateAccount {
        from: ctx.accounts.payer,
        to: ctx.accounts.pool,
        lamports: lamports_needed,
        space: space_needed as u64,
        owner: &crate::ID,
    }
    .invoke_signed(&[Signer::from(&[
        Seed::from(b"pool".as_ref()),
        Seed::from(args.pool_id.as_ref()),
        Seed::from(ctx.accounts.creator.key().as_ref()),
        Seed::from(&[bump]),
    ])])?;

    let mut init_vec = Vec::with_capacity(208);
    pool.serialize(&mut init_vec)
        .map_err(|_| ChickenError::SerializationError)?;

    unsafe {
        let account_data_ptr = ctx.accounts.pool.borrow_mut_data_unchecked();
        sol_memmove(
            account_data_ptr.as_mut_ptr(),
            init_vec.as_mut_ptr(),
            space_needed,
        );
    }
    Ok(())
}
