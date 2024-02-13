// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/src/Test.sol";

import "juice-contracts-v4/src/JBController.sol";
import "juice-contracts-v4/src/JBDirectory.sol";
import "juice-contracts-v4/src/JBMultiTerminal.sol";
import "juice-contracts-v4/src/JBFundAccessLimits.sol";
import "juice-contracts-v4/src/JBTerminalStore.sol";
import "juice-contracts-v4/src/JBRulesets.sol";
import "juice-contracts-v4/src/JBFeelessAddresses.sol";
import "juice-contracts-v4/src/JBPermissions.sol";
import "juice-contracts-v4/src/JBPrices.sol";
import "juice-contracts-v4/src/JBProjects.sol";
import "juice-contracts-v4/src/JBSplits.sol";
import "juice-contracts-v4/src/JBTokens.sol";

import "juice-contracts-v4/src/structs/JBAfterPayRecordedContext.sol";
import "juice-contracts-v4/src/structs/JBAfterRedeemRecordedContext.sol";
import "juice-contracts-v4/src/structs/JBFee.sol";
import "juice-contracts-v4/src/structs/JBFundAccessLimitGroup.sol";
import "juice-contracts-v4/src/structs/JBRuleset.sol";
import "juice-contracts-v4/src/structs/JBRulesetMetadata.sol";
import "juice-contracts-v4/src/structs/JBSplitGroup.sol";
import "juice-contracts-v4/src/structs/JBPermissionsData.sol";
import "juice-contracts-v4/src/structs/JBBeforePayRecordedContext.sol";
import "juice-contracts-v4/src/structs/JBBeforeRedeemRecordedContext.sol";
import "juice-contracts-v4/src/structs/JBSplit.sol";
import "juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import "juice-contracts-v4/src/interfaces/IJBToken.sol";
import "juice-contracts-v4/src/libraries/JBConstants.sol";
import "juice-contracts-v4/src/interfaces/IJBTerminalStore.sol";

import "src/interfaces/external/IWETH9.sol";
import "src/JBBuybackHook.sol";

/// @notice Basic test setup for buyback hook tests. Deploys and pre-configures common contracts.
contract TestBaseWorkflowV3 is Test {
    using stdStorage for StdStorage;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    // Multisig (project owner) and beneficiary addresses used for testing.
    address internal multisig = makeAddr("mooltichig");
    address internal beneficiary = makeAddr("benefishary");

    JBPermissions internal jbPermissions;
    JBProjects internal jbProjects;
    JBPrices internal jbPrices;
    JBDirectory internal jbDirectory;
    JBFundAccessLimits internal jbFundAccessLimits;
    JBRulesets internal jbRulesets;
    JBFeelessAddresses internal jbFeelessAddresses;
    JBTokens internal jbTokens;
    JBSplits internal jbSplits;
    JBController internal jbController;
    JBTerminalStore internal jbTerminalStore;
    JBMultiTerminal internal jbMultiTerminal;

    JBBuybackHook hook;

    uint256 projectId;
    uint256 reservedRate = 4500;
    uint256 weight = 10 ether; // Minting 10 token per eth
    uint32 cardinality = 1000;
    uint256 twapDelta = 500;

    JBRulesetMetadata metadata;

    // Use the old JBX<->ETH pair with a 1% fee as the `UniswapV3Pool` throughout tests.
    // IUniswapV3Pool pool = IUniswapV3Pool(0x48598Ff1Cee7b4d31f8f9050C2bbAE98e17E6b17);
    IJBToken jbx = IJBToken(0x3abF2A4f8452cCC2CF7b4C1e4663147600646f66);
    IWETH9 weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    uint24 fee = 10;

    IUniswapV3Pool pool;

    //*********************************************************************//
    // --------------------------- test setup ---------------------------- //
    //*********************************************************************//

    // Deploys and initializes contracts for testing.
    function setUp() public virtual {
        // Labels.
        vm.label(multisig, "projectOwner");
        vm.label(beneficiary, "beneficiary");
        vm.label(address(pool), "uniswapPool");
        vm.label(address(uniswapFactory), "uniswapFactory");
        vm.label(address(weth), "$WETH");
        vm.label(address(jbx), "$JBX");

        // Mock.
        vm.etch(address(pool), "0x69");
        vm.etch(address(weth), "0x69");

        // JBPermissions
        jbPermissions = new JBPermissions();
        vm.label(address(jbPermissions), "JBPermissions");

        // JBProjects
        jbProjects = new JBProjects(multisig);
        vm.label(address(jbProjects), "JBProjects");

        // JBPrices
        jbPrices = new JBPrices(jbPermissions, jbProjects, multisig);
        vm.label(address(jbPrices), "JBPrices");

        // JBDirectory
        jbDirectory = new JBDirectory(jbPermissions, jbProjects, multisig);
        vm.label(address(jbDirectory), "JBDirectory");

        // JBRulesets
        jbRulesets = new JBRulesets(jbDirectory);
        vm.label(address(jbRulesets), "JBRulesets");

        // JBTokens
        jbTokens = new JBTokens(jbDirectory);
        vm.label(address(jbTokens), "JBTokens");

        // JBSplits
        jbSplits = new JBSplits(jbDirectory);
        vm.label(address(jbSplits), "JBSplits");

        // JBFundAccessLimits
        jbFundAccessLimits = new JBFundAccessLimits(jbDirectory);
        vm.label(address(jbFundAccessLimits), "JBFundAccessLimits");

        // JBFeelessAddresses
        jbFeelessAddresses = new JBFeelessAddresses(address(69));
        vm.label(address(jbFeelessAddresses), "JBFeelessAddresses");

        // JBController
        jbController = new JBController(
            jbPermissions, jbProjects, jbDirectory, jbRulesets, jbTokens, jbSplits, jbFundAccessLimits, address(0)
        );
        vm.label(address(jbController), "JBController");

        vm.prank(multisig);
        jbDirectory.setIsAllowedToSetFirstController(address(jbController), true);

        // JBTerminalStore
        jbTerminalStore = new JBTerminalStore(jbDirectory, jbRulesets, jbPrices);
        vm.label(address(jbTerminalStore), "JBTerminalStore");

        // JBMultiTerminal
        jbMultiTerminal = new JBMultiTerminal(
            jbPermissions,
            jbProjects,
            jbDirectory,
            jbSplits,
            jbTerminalStore,
            jbFeelessAddresses,
            IPermit2(address(0)),
            address(0)
        );
        vm.label(address(jbMultiTerminal), "JBMultiTerminal");

        // Deploy the buyback hook.
        hook = new JBBuybackHook({
            weth: weth,
            factory: uniswapFactory,
            directory: IJBDirectory(address(jbDirectory)),
            controller: jbController
        });

        // Ruleset metadata: use the hook for payments.
        metadata = JBRulesetMetadata({
            reservedRate: reservedRate,
            redemptionRate: 5000,
            baseCurrency: uint32(uint160(JBConstants.NATIVE_TOKEN)),
            pausePay: false,
            pauseCreditTransfers: false,
            allowOwnerMinting: false,
            allowTerminalMigration: false,
            allowSetTerminals: false,
            allowControllerMigration: false,
            allowSetController: false,
            holdFees: false,
            useTotalSurplusForRedemptions: true,
            useDataHookForPay: true,
            useDataHookForRedeem: false,
            dataHook: address(hook),
            metadata: 0
        });

        // More ruleset configuration.
        JBFundAccessLimitGroup[] memory fundAccessLimitGroups = new JBFundAccessLimitGroup[](1);
        JBCurrencyAmount[] memory payoutLimits = new JBCurrencyAmount[](1);
        JBCurrencyAmount[] memory surplusAllowances = new JBCurrencyAmount[](1);
        payoutLimits[0] = JBCurrencyAmount({amount: 2 ether, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});
        surplusAllowances[0] =
            JBCurrencyAmount({amount: type(uint232).max, currency: uint32(uint160(JBConstants.NATIVE_TOKEN))});
        fundAccessLimitGroups[0] = JBFundAccessLimitGroup({
            terminal: address(jbMultiTerminal),
            token: JBConstants.NATIVE_TOKEN,
            payoutLimits: payoutLimits,
            surplusAllowances: surplusAllowances
        });

        // Package up the ruleset configuration.
        JBRulesetConfig[] memory rulesetConfigurations = new JBRulesetConfig[](1);
        rulesetConfigurations[0].mustStartAtOrAfter = 0;
        rulesetConfigurations[0].duration = 6 days;
        rulesetConfigurations[0].weight = weight;
        rulesetConfigurations[0].decayRate = 0;
        rulesetConfigurations[0].approvalHook = IJBRulesetApprovalHook(address(0));

        rulesetConfigurations[0].metadata = metadata;
        rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
        rulesetConfigurations[0].fundAccessLimitGroups = fundAccessLimitGroups;

        JBTerminalConfig[] memory terminalConfigurations = new JBTerminalConfig[](1);
        address[] memory tokensToAccept = new address[](1);
        tokensToAccept[0] = JBConstants.NATIVE_TOKEN;
        terminalConfigurations[0] = JBTerminalConfig({terminal: jbMultiTerminal, tokensToAccept: tokensToAccept});

        // Launch the project with the `multisig` as the owner.
        projectId = jbController.launchProjectFor({
            owner: multisig,
            projectUri: "myIPFSHash",
            rulesetConfigurations: rulesetConfigurations,
            terminalConfigurations: terminalConfigurations, // Set terminals to receive fees.
            memo: ""
        });

        // Deploy the JBX ERC-20 for the project.
        vm.prank(multisig);
        jbController.deployERC20For(projectId, "jbx", "jbx");

        // Set the buyback hook pool up for the project.
        vm.prank(multisig);
        pool = hook.setPoolFor(projectId, fee, uint32(cardinality), twapDelta, address(weth));
    }
}
