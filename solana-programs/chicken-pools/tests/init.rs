mod common;
use borsh::{BorshDeserialize, BorshSerialize};
use chicken::{actions::InitializePoolArgs, Instruction as ChickenInstruction};
use common::*;
use litesvm_token::spl_token::{self, solana_program};
use solana_sdk::{
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::Keypair,
    signer::Signer,
    system_program,
    transaction::Transaction,
};

#[test_log::test]
fn test_init() -> anyhow::Result<()> {
    let mut ctx = setup_test_context()?;
    let args = InitializePoolArgs {
        pool_id: ctx.pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot,
        end_time: ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot + 100,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, args.clone())?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let chicken = chicken::state::Pool::deserialize(&mut pool.data.as_slice()).unwrap();
    assert_eq!(chicken.state, chicken::state::PoolState::Pending);
    assert_eq!(chicken.deposit_fee_bps, 10);
    assert_eq!(chicken.withdraw_fee_bps, 10);
    assert_eq!(chicken.collateral_bps, 500);
    assert_eq!(chicken.mode, chicken::state::PoolMode::LastOutWinner);
    assert_eq!(
        chicken.start_time,
        ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot
    );
    assert_eq!(
        chicken.end_time,
        ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot + 100
    );
    assert_eq!(chicken.min_deposit, 0);
    assert_eq!(chicken.pool_id, args.pool_id);
    assert_eq!(chicken.authority, ctx.creator.pubkey().to_bytes());
    assert_eq!(chicken.collateral_mint, ctx.mint.to_bytes());
    Ok(())
}

#[test_log::test]
fn test_bad_token_accounts() -> anyhow::Result<()> {
    let ctx = setup_test_context()?;
    let mut svm = ctx.svm;
    let creator = Keypair::new();
    svm.airdrop(&creator.pubkey(), 10000000000000).unwrap();
    let pool_id = [0; 16];
    let (pool_key, _) = Pubkey::find_program_address(
        &[
            b"pool".as_ref(),
            pool_id.as_ref(),
            creator.pubkey().as_ref(),
        ],
        &program_id(),
    );
    let mut writer = std::io::Cursor::new(vec![]);
    let args = InitializePoolArgs {
        pool_id,
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: svm.get_sysvar::<solana_program::clock::Clock>().slot,
        end_time: svm.get_sysvar::<solana_program::clock::Clock>().slot + 100,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    let init_ix = ChickenInstruction::InitializePool(args);
    init_ix.serialize(&mut writer).unwrap();
    let random_key_pair = Keypair::new();
    let random_key_pair2 = Keypair::new();
    let ix = Instruction::new_with_bytes(
        program_id(),
        writer.get_ref(),
        vec![
            AccountMeta::new(pool_key, false),
            AccountMeta::new_readonly(creator.pubkey(), true),
            AccountMeta::new_readonly(creator.pubkey(), true),
            AccountMeta::new(random_key_pair.pubkey(), false),
            AccountMeta::new(random_key_pair2.pubkey(), false),
            AccountMeta::new_readonly(spl_token::ID, false),
            AccountMeta::new_readonly(system_program::ID, false),
        ],
    );
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&creator.pubkey()),
        &[&creator],
        svm.latest_blockhash(),
    );
    let rest_error = svm.send_transaction(tx).unwrap_err();
    assert_eq!(
        rest_error.err.to_string(),
        "Error processing Instruction 0: custom program error: 0x1"
    );
    Ok(())
}
