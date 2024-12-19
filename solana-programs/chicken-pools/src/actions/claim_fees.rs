use super::update_pool_state;
use crate::{    
    assertions::{account_empty, check_self_pda, find_self_pda}, error::ChickenError, state::{Pool, PoolState}, ChangeAdminAccounts, ClaimFeesAccounts, Context, InitializeAdminAccounts
};

use borsh::BorshDeserialize;
use pinocchio::{
    instruction::{Seed, Signer}, memory::{sol_memcpy, sol_memset}, sysvars::{clock::Clock, rent::Rent, Sysvar}, ProgramResult
};
use pinocchio_system::instructions::CreateAccount;
use pinocchio_token::{instructions::TransferChecked, state::{Mint, TokenAccount}};



pub fn claim_fees(ctx: Context<ClaimFeesAccounts>) -> ProgramResult {
    let get_admin_record: &[u8] = unsafe { ctx.accounts.admin_record.borrow_data_unchecked() };
    if get_admin_record != ctx.accounts.admin.key().as_ref() {
        return Err(ChickenError::Unauthorized.into());
    }
    let current_slot = Clock::get()?.slot;
    let pd = unsafe { ctx.accounts.pool.borrow_mut_data_unchecked() };
    let mut pool = Pool::try_from_slice(pd).map_err(|_| ChickenError::DeserializationError)?;
    update_pool_state(&mut pool, current_slot)?;
    if pool.state != PoolState::Ended {
        return Err(ChickenError::PoolNotEnded.into());
    }
    let mint = Mint::from_account_info(ctx.accounts.collateral_mint)?;
    let pool_collateral_token_account = TokenAccount::from_account_info(
        ctx.accounts.pool_collateral_token_account
    )?;
    let admin_token_account =
        TokenAccount::from_account_info(ctx.accounts.admin_token_account)?;
    if admin_token_account.owner() != ctx.accounts.admin.key() {
        return Err(ChickenError::Unauthorized.into());
    }
    let cm_key = ctx.accounts.collateral_mint.key();
    if pool_collateral_token_account.mint() != cm_key {
        return Err(ChickenError::InvalidTokenAccount.into());
    }
    if pool_collateral_token_account.owner() != ctx.accounts.pool.key() {
        return Err(ChickenError::InvalidTokenAccount.into());
    }
    if cm_key != &pool.collateral_mint {
        return Err(ChickenError::InvalidMint.into());
    }
    let fee_amount = pool.fee_amount;
    pool.fee_amount = 0;
    TransferChecked {
        from: ctx.accounts.pool_collateral_token_account,
        to: ctx.accounts.admin_token_account,
        authority: ctx.accounts.pool,
        amount: fee_amount,
        mint: ctx.accounts.collateral_mint,
        decimals: mint.decimals(),
    }
    .invoke_signed(&[Signer::from(&[
        Seed::from(b"pool".as_ref()),
        Seed::from(pool.pool_id.as_ref()),
        Seed::from(pool.creator.as_ref()),
        Seed::from(&[pool.bump]),
    ])])?;
    Ok(())
}

pub fn initialize_admin(ctx: Context<InitializeAdminAccounts>) -> ProgramResult {
    if !ctx.accounts.admin.is_signer() {
        return Err(ChickenError::Unauthorized.into());
    }
    let bump = if account_empty(ctx.accounts.admin_record) {
        let bump = find_self_pda(
            &[
                b"admin".as_ref(),
            ],
            ctx.accounts.admin_record.key(),
            ChickenError::InvalidAdminRecordAddress,
        )?;
        CreateAccount {
            from: ctx.accounts.admin,
            to: ctx.accounts.admin_record,
            lamports: Rent::get()?.minimum_balance(33),
            space: 33,
            owner: &crate::ID,
        }.invoke_signed(
            &[Signer::from(&[
                Seed::from(b"admin".as_ref()),
                Seed::from(&[bump]),
            ])]
        )?;
        bump
    } else {
        unsafe {
            ctx.accounts.admin_record.borrow_mut_data_unchecked()[32]
        }
    };
    unsafe {
        sol_memcpy(
            &mut ctx.accounts.admin_record.borrow_mut_data_unchecked(),
            [ctx.accounts.admin.key().as_ref(), &[bump]].concat().as_ref(),
            33,
        );
    }
    Ok(())
}

pub fn change_admin(ctx: Context<ChangeAdminAccounts>) -> ProgramResult {
    let get_admin_record = unsafe { ctx.accounts.admin_record.borrow_mut_data_unchecked() };
    if !ctx.accounts.admin.is_signer() {
        return Err(ChickenError::Unauthorized.into());
    }
    if &get_admin_record[0..32] != ctx.accounts.admin.key().as_ref() {
        return Err(ChickenError::Unauthorized.into());
    }
    check_self_pda(
        &[
            b"admin".as_ref(),
            &get_admin_record[32..],
        ],
        ctx.accounts.admin_record.key(),
        ChickenError::InvalidAdminRecordAddress,
    )?;
    unsafe { sol_memcpy(
        get_admin_record,
        ctx.accounts.new_admin.key().as_ref(),
        32,
    ) };
    Ok(())
}
