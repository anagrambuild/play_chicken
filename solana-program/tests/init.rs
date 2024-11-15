mod common;
use borsh::BorshDeserialize;
use chicken::{actions::InitializePoolArgs, ID};
use common::*;
use litesvm::LiteSVM;
use solana_program::pubkey::Pubkey;
use solana_sdk::{signature::Keypair, signer::Signer};

#[test_log::test]
fn test_init() -> anyhow::Result<()> {
    let mut ctx = setup_test_context()?;
    let args = InitializePoolArgs {
        pool_id: [0; 16],
        pool_mode: chicken::state::PoolMode::LastOutWinner,
        start_time: ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot,
        end_time: ctx.svm.get_sysvar::<solana_program::clock::Clock>().slot + 100,
        minimum_deposit: 0,
        collateral_bps: 500,
        max_deposit: None,
        total_deposit_limit: None,
    };
    setup_pool(&mut ctx, &args)?;
    let pool = ctx.svm.get_account(&ctx.pool_key).unwrap();
    let chicken = chicken::state::Pool::deserialize(&mut &pool.data[8..]).unwrap();
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
    assert_eq!(chicken.authority, ctx.creator.pubkey());
    assert_eq!(chicken.collateral_mint, ctx.mint);
    Ok(())
}
