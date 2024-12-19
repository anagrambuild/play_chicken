pub mod actions;
pub mod error;
pub mod state;

use accounts::*;
use actions::*;
use borsh::{BorshDeserialize, BorshSerialize};
mod assertions;

use error::ChickenError;
use pinocchio::account_info::AccountInfo;
use pinocchio::program_error::ProgramError;
use pinocchio::pubkey::Pubkey;
use pinocchio::ProgramResult;
use shank::{ShankContext, ShankInstruction};

pub const DEPOSIT_FEE_BPS: u16 = 10;
pub const WITHDRAW_FEE_BPS: u16 = 10;

use pinocchio_pubkey::declare_id;

declare_id!("chknZh1FSSbASjrsFxTVPphCLQqeENFJJ2yTofyk3kB");

#[cfg(not(feature = "no-entrypoint"))]
use pinocchio::entrypoint;

#[cfg(not(feature = "no-entrypoint"))]
entrypoint!(process_instruction);

fn process_instruction(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    instruction_data: &[u8],
) -> ProgramResult {
    let ix = Instruction::try_from_slice(instruction_data)
        .map_err(|_| ChickenError::InvalidInstructionData)?;
    match ix {
        Instruction::InitializePool(args) => {
            let ctx = accounts::InitializePoolAccounts::context(accounts)?;
            initialize_pool(ctx, args)
        }
       
        Instruction::Deposit(amount) => {
            let ctx = DepositAccounts::context(accounts)?;
            deposit(ctx, amount)
        }
        Instruction::Withdraw => {
            let ctx = WithdrawAccounts::context(accounts)?;
            withdraw(ctx)
        }
        _ => Err(ChickenError::InvalidInstructionData.into()),
        
        Instruction::RemovePool => {
            let ctx = RemovePoolAccounts::context(accounts)?;
            remove_pool(ctx)
        }
        Instruction::ClaimFees => {
            let ctx = ClaimFeesAccounts::context(accounts)?;
            claim_fees(ctx)
        }
        Instruction::InitializeAdmin => {
            let ctx = InitializeAdminAccounts::context(accounts)?;
            initialize_admin(ctx)
        }
        Instruction::ChangeAdmin => {
            let ctx = ChangeAdminAccounts::context(accounts)?;
            change_admin(ctx)
        }
    }
}

#[derive(ShankContext, ShankInstruction, BorshDeserialize, BorshSerialize)]
#[rustfmt::skip]
#[repr(u8)]
pub enum Instruction {
    #[account(0, writable, name="pool", desc="the pool")]
    #[account(1, writable, signer, name="creator", desc="the creator of the pool")]
    #[account(2, writable, signer, name="payer", desc="the payer")]
    #[account(3, name="pool_collateral_mint", desc="the collateral mint of the pool")]
    #[account(4, writable, name="pool_collateral_token_account", desc="the collateral token account of the pool")]
    #[account(5, name="token_program", desc="the token program")]
    #[account(6, name="system_program", desc="the system program")]
    InitializePool(InitializePoolArgs),
    #[account(0, writable, name="pool", desc="the pool")]
    #[account(1, writable,signer, name="user", desc="the user")]
    #[account(2, writable, signer, name="payer", desc="the payer")]
    #[account(3, writable, name="pool_collateral_token_account", desc="the collateral token account of the pool")]
    #[account(4, writable, name="user_collateral_token_account", desc="the collateral token account of the user")]
    #[account(5, writable, name="user_position", desc="the user position")]
    #[account(6, name="colateral_mint", desc="the collateral mint of the pool")]
    #[account(7, name="token_program", desc="the token program")]
    #[account(8, name="system_program", desc="the system program")]
    Deposit(u64),
    #[account(0, writable, name="pool", desc="the pool")]
    #[account(1, writable, signer,name="payer", desc="the payer")]
    #[account(2, writable, signer, name="user", desc="the user")]
    #[account(3, writable, name="pool_collateral_token_account", desc="the collateral token account of the pool")]
    #[account(4, writable, name="user_collateral_token_account", desc="the collateral token account of the user")]
    #[account(5, writable, name="user_position", desc="the user position")]
    #[account(6, name="colateral_mint", desc="the collateral mint of the pool")]
    #[account(7, name="token_program", desc="the token program")]
    #[account(8, name="system_program", desc="the system program")]
    Withdraw,
    #[account(0, writable, name="pool", desc="the pool")]
    #[account(1, writable, signer, name="creator", desc="the creator of the pool")]
    #[account(2, name="payer", signer, desc="the payer")]
    #[account(3, name="system_program", desc="the system program")]
    RemovePool,
    #[account(0, writable, name="pool", desc="the pool")]
    #[account(1, writable, name="pool_collateral_token_account", desc="the collateral token account of the pool")]
    #[account(2, writable, name="admin_token_account", desc="the admin token account of the pool")]
    #[account(3, name="admin", signer, desc="the admin")]
    #[account(4, name="admin_record", desc="the admin record")]
    #[account(5, name="collateral_mint", desc="the collateral mint of the pool")]
    #[account(6, name="token_program", desc="the token program")]
    ClaimFees,
    #[account(0, writable, name="admin_record", desc="the admin record")]
    #[account(1, writable, signer, name="admin", signer, desc="the admin")]
    #[account(2, name="system_program", desc="the system program")]
    InitializeAdmin,
    #[account(0, writable, name="admin_record", desc="the admin record")]
    #[account(1, writable, signer, name="admin", signer, desc="the admin")] 
    #[account(2, writable, signer, name="new_admin", signer, desc="the new admin")]
    #[account(3, name="system_program", desc="the system program")]
    ChangeAdmin,
}
