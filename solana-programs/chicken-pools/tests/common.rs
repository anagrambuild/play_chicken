use anyhow::Result;
use borsh::BorshSerialize;
use chicken::{actions::InitializePoolArgs, Instruction as ChickenInstruction};
use litesvm::LiteSVM;
use litesvm_token::{spl_token, CreateAssociatedTokenAccount, CreateMint, MintTo};

use solana_sdk::{
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::Keypair,
    signer::Signer,
    system_program,
    transaction::Transaction,
};
use spl_associated_token_account_client::address::get_associated_token_address_with_program_id;

pub fn program_id() -> Pubkey {
    Pubkey::from(chicken::ID)
}

pub fn load_program(svm: &mut LiteSVM) -> anyhow::Result<()> {
    svm.add_program_from_file(program_id(), "../../target/deploy/chicken.so")
        .map_err(|e| anyhow::anyhow!("Failed to load program {:?}", e))
}

pub fn setup_mint(
    svm: &mut LiteSVM,
    payer: &Keypair,
    pool: &Pubkey,
) -> anyhow::Result<(Pubkey, Pubkey)> {
    let mint = CreateMint::new(svm, payer)
        .decimals(9)
        .token_program_id(&spl_token::ID)
        .send()
        .map_err(|e| anyhow::anyhow!("Failed to create mint {:?}", e))?;
    let ata = CreateAssociatedTokenAccount::new(svm, payer, &mint)
        .owner(pool)
        .send()
        .map_err(|_| anyhow::anyhow!("Failed to create associated token account"))?;

    Ok((mint, ata))
}

pub fn mint_to(
    svm: &mut LiteSVM,
    mint: &Pubkey,
    authority: &Keypair,
    to: &Pubkey,
    amount: u64,
) -> Result<(), anyhow::Error> {
    MintTo::new(svm, authority, mint, to, amount)
        .send()
        .map_err(|e| anyhow::anyhow!("Failed to mint {:?}", e))?;
    Ok(())
}

pub fn setup_ata(
    svm: &mut LiteSVM,
    mint: &Pubkey,
    user: &Keypair,
) -> Result<Pubkey, anyhow::Error> {
    CreateAssociatedTokenAccount::new(svm, user, mint)
        .owner(&user.pubkey())
        .send()
        .map_err(|_| anyhow::anyhow!("Failed to create associated token account"))
}

pub fn init_pool(
    svm: &mut LiteSVM,
    creator: &Keypair,
    mint: &Pubkey,
    pool: &Pubkey,
    pool_init_args: InitializePoolArgs,
) -> Result<(), anyhow::Error> {
    let mut writer = std::io::Cursor::new(vec![]);
    ChickenInstruction::InitializePool(pool_init_args)
        .serialize(&mut writer)
        .unwrap();
    let pool_ata = get_associated_token_address_with_program_id(pool, mint, &spl_token::ID);
    let ix = Instruction::new_with_bytes(
        program_id(),
        writer.get_ref(),
        vec![
            AccountMeta::new(*pool, false),
            AccountMeta::new_readonly(creator.pubkey(), true),
            AccountMeta::new(creator.pubkey(), true),
            AccountMeta::new(*mint, false),
            AccountMeta::new(pool_ata, false),
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
    svm.send_transaction(tx)
        .map_err(|e| anyhow::anyhow!("Failed to send transaction: {:?}", e))?;
    Ok(())
}

pub fn deposit(svm: &mut LiteSVM, mint: &Pubkey, pool: &Pubkey, user: &Keypair, amount: u64) -> Result<Pubkey, anyhow::Error> {
    deposit_logs(svm, mint, pool, user, amount, false)
}

pub fn deposit_logs(
    svm: &mut LiteSVM,
    mint: &Pubkey,
    pool: &Pubkey,
    user: &Keypair,
    amount: u64,
    print_logs: bool,
) -> Result<Pubkey, anyhow::Error> {
    let user_position = Pubkey::find_program_address(
        &[
            b"user_position".as_ref(),
            pool.as_ref(),
            user.pubkey().as_ref(),
        ],
        &program_id(),
    )
    .0;
    let pool_ata = get_associated_token_address_with_program_id(pool, mint, &spl_token::ID);
    let user_ata =
        get_associated_token_address_with_program_id(&user.pubkey(), mint, &spl_token::ID);
    let mut writer = std::io::Cursor::new(vec![]);
    ChickenInstruction::Deposit(amount)
        .serialize(&mut writer)
        .unwrap();
    let ix = Instruction::new_with_bytes(
        program_id(),
        writer.get_ref(),
        vec![
            AccountMeta::new(*pool, false),
            AccountMeta::new_readonly(user.pubkey(), true),
            AccountMeta::new(user.pubkey(), true),
            AccountMeta::new(pool_ata, false),
            AccountMeta::new(user_ata, false),
            AccountMeta::new(user_position, false),
            AccountMeta::new(*mint, false),
            AccountMeta::new_readonly(spl_token::ID, false),
            AccountMeta::new_readonly(system_program::ID, false),
        ],
    );
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&user.pubkey()),
        &[&user],
        svm.latest_blockhash(),
    );
    let res = svm.send_transaction(tx)
        .map_err(|e| anyhow::anyhow!("Failed to send transaction: {:?}", e))?;
    if print_logs {
        println!("{:?}", res.logs);
    }
    Ok(user_position)
}

pub fn withdraw(svm: &mut LiteSVM, pool: &Pubkey, mint: &Pubkey, user: &Keypair) -> Result<(), anyhow::Error> {
    withdraw_logs(svm, pool, mint, user, false)
}
    

pub fn withdraw_logs(
    svm: &mut LiteSVM,
    pool: &Pubkey,
    mint: &Pubkey,
    user: &Keypair,
    print_logs: bool,
) -> Result<(), anyhow::Error> {
    let mut writer = std::io::Cursor::new(vec![]);
    ChickenInstruction::Withdraw.serialize(&mut writer).unwrap();
    let user_position = Pubkey::find_program_address(
        &[
            b"user_position".as_ref(),
            pool.as_ref(),
            user.pubkey().as_ref(),
        ],
        &program_id(),
    )
    .0;
    let pool_ata = get_associated_token_address_with_program_id(pool, mint, &spl_token::ID);
    let user_ata =
        get_associated_token_address_with_program_id(&user.pubkey(), mint, &spl_token::ID);
    let ix = Instruction::new_with_bytes(
        program_id(),
        writer.get_ref(),
        vec![
            AccountMeta::new(*pool, false),
            AccountMeta::new(user.pubkey(), true),
            AccountMeta::new(user.pubkey(), true),
            AccountMeta::new(pool_ata, false),
            AccountMeta::new(user_ata, false),
            AccountMeta::new(user_position, false),
            AccountMeta::new_readonly(*mint, false),
            AccountMeta::new_readonly(spl_token::ID, false),
            AccountMeta::new_readonly(system_program::ID, false),
        ],
    );
    let tx = Transaction::new_signed_with_payer(
        &[ix],
        Some(&user.pubkey()),
        &[&user],
        svm.latest_blockhash(),
    );
    let res = svm
        .send_transaction(tx)
        .map_err(|e| anyhow::anyhow!("Failed to send transaction: {:?}", e))?;
    if print_logs {
        println!("{:?}", res.logs);
    }
    Ok(())
}

pub struct TestContext {
    pub svm: LiteSVM,
    pub mint: Pubkey,
    pub pool_key: Pubkey,
    pub pool_id: [u8; 16],
    pub pool_bump: u8,
    pub pool_ata: Pubkey,
    pub mint_authority: Keypair,
    pub creator: Keypair,
}

pub fn setup_test_context() -> Result<TestContext> {
    let mut svm = LiteSVM::new();
    load_program(&mut svm)?;

    let mint_authority = Keypair::new();
    svm.airdrop(&mint_authority.pubkey(), 10000000).unwrap();

    let creator = Keypair::new();
    svm.airdrop(&creator.pubkey(), 10000000).unwrap();

    let pool_id = [0; 16];
    let (pool_key, pool_bump) = Pubkey::find_program_address(
        &[
            b"pool".as_ref(),
            pool_id.as_ref(),
            creator.pubkey().as_ref(),
        ],
        &program_id(),
    );

    let (mint, pool_ata) = setup_mint(&mut svm, &mint_authority, &pool_key)?;

    Ok(TestContext {
        svm,
        mint,
        pool_key,
        pool_id,
        pool_bump,
        pool_ata,
        mint_authority,
        creator,
    })
}

pub fn setup_pool(ctx: &mut TestContext, args: InitializePoolArgs) -> Result<()> {
    init_pool(&mut ctx.svm, &ctx.creator, &ctx.mint, &ctx.pool_key, args)
}

pub fn setup_user(ctx: &mut TestContext, amount: u64) -> Result<(Keypair, Pubkey)> {
    let user = Keypair::new();
    ctx.svm.airdrop(&user.pubkey(), 10000000000).unwrap();
    let user_ata = setup_ata(&mut ctx.svm, &ctx.mint, &user)?;
    mint_to(
        &mut ctx.svm,
        &ctx.mint,
        &ctx.mint_authority,
        &user_ata,
        amount,
    )?;
    Ok((user, user_ata))
}
