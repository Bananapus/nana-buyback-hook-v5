// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "lib/forge-std/src/Test.sol";

import "lib/juice-contracts-v4/src/JBController.sol";
import "lib/juice-contracts-v4/src/JBDirectory.sol";
import "lib/juice-contracts-v4/src/JBMultiTerminal.sol";
import "lib/juice-contracts-v4/src/JBFundAccessLimits.sol";
import "lib/juice-contracts-v4/src/JBTerminalStore.sol";
import "lib/juice-contracts-v4/src/JBRulesets.sol";
import "lib/juice-contracts-v4/src/JBPermissions.sol";
import "lib/juice-contracts-v4/src/JBPrices.sol";
import "lib/juice-contracts-v4/src/JBProjects.sol";
import "lib/juice-contracts-v4/src/JBSplits.sol";
import "lib/juice-contracts-v4/src/JBTokens.sol";

import "lib/juice-contracts-v4/src/structs/JBDidPayData.sol";
import "lib/juice-contracts-v4/src/structs/JBDidRedeemData.sol";
import "lib/juice-contracts-v4/src/structs/JBFee.sol";
import "lib/juice-contracts-v4/src/structs/JBFundAccessLimitGroup.sol";
import "lib/juice-contracts-v4/src/structs/JBRuleset.sol";
import "lib/juice-contracts-v4/src/structs/JBRulesetData.sol";
import "lib/juice-contracts-v4/src/structs/JBRulesetMetadata.sol";
import "lib/juice-contracts-v4/src/structs/JBSplitGroup.sol";
import "lib/juice-contracts-v4/src/structs/JBPermissionsData.sol";
import "lib/juice-contracts-v4/src/structs/JBPayParamsData.sol";
import "lib/juice-contracts-v4/src/structs/JBRedeemParamsData.sol";
import "lib/juice-contracts-v4/src/structs/JBSplit.sol";
import "lib/juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import "lib/juice-contracts-v4/src/interfaces/IJBToken.sol";
import "lib/juice-contracts-v4/src/libraries/JBConstants.sol";

import "lib/juice-contracts-v4/src/interfaces/IJBTerminalStore.sol";

import "./AccessJBLib.sol";
import "src/interfaces/external/IWETH9.sol";
import "src/JBBuybackHook.sol";

// Base contract for Juicebox system tests.
//
// Provides common functionality, such as deploying contracts on test setup for v3.
contract TestBaseWorkflowV3 is Test {
    using stdStorage for StdStorage;

    //*********************************************************************//
    // -------------------- internal stored properties ------------------- //
    //*********************************************************************//

    // Multisig address used for testing.
    address internal _multisig = makeAddr("mooltichig");
    address internal _beneficiary = makeAddr("benefishary");

    JBPermissions internal _jbPermissions;
    JBProjects internal _jbProjects;
    JBPrices internal _jbPrices;
    JBDirectory internal _jbDirectory;
    JBFundAccessLimits internal _fundAccessConstraintsStore;
    JBRulesets internal _jbRulesets;
    JBTokens internal _jbTokens;
    JBSplits internal _jbSplits;
    JBController internal _jbController;
    JBTerminalStore internal _jbPaymentTerminalStore;
    JBMultiTerminal internal _jbETHPaymentTerminal;
    AccessJBLib internal _accessJBLib;

    JBBuybackHook _delegate;

    uint256 _projectId;
    uint256 reservedRate = 4500;
    uint256 weight = 10 ether; // Minting 10 token per eth
    uint32 cardinality = 1000;
    uint256 twapDelta = 500;

    JBRulesetData _data;
    JBRulesetData _dataReconfiguration;
    JBRulesetData _dataWithoutBallot;
    JBRulesetMetadata _metadata;
    JBFundAccessLimitGroup _fundAccessLimitGroup; // Default empty

    // Use the L1 UniswapV3Pool jbx/eth 1% fee for create2 magic
    // IUniswapV3Pool pool = IUniswapV3Pool(0x48598Ff1Cee7b4d31f8f9050C2bbAE98e17E6b17);
    IJBToken jbx = IJBToken(0x3abF2A4f8452cCC2CF7b4C1e4663147600646f66);
    IWETH9 weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address _uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    uint24 fee = 10_000;

    IUniswapV3Pool pool;

    //*********************************************************************//
    // ------------------------- internal views -------------------------- //
    //*********************************************************************//

    function jbLibraries() internal view returns (AccessJBLib) {
        return _accessJBLib;
    }

    //*********************************************************************//
    // --------------------------- test setup ---------------------------- //
    //*********************************************************************//

    // Deploys and initializes contracts for testing.
    function setUp() public virtual {
        // Labels
        vm.label(_multisig, "projectOwner");
        vm.label(_beneficiary, "beneficiary");
        vm.label(address(pool), "uniswapPool");
        vm.label(address(_uniswapFactory), "uniswapFactory");
        vm.label(address(weth), "$WETH");
        vm.label(address(jbx), "$JBX");

        // mock
        vm.etch(address(pool), "0x69");
        vm.etch(address(weth), "0x69");

        // JBPermissions
        _jbPermissions = new JBPermissions();
        vm.label(address(_jbPermissions), "JBPermissions");

        // JBProjects
        _jbProjects = new JBProjects(_jbPermissions);
        vm.label(address(_jbProjects), "JBProjects");

        // JBPrices
        _jbPrices = new JBPrices(_multisig);
        vm.label(address(_jbPrices), "JBPrices");

        address contractAtNoncePlusOne = computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        // JBRulesets
        _jbRulesets = new JBRulesets(IJBDirectory(contractAtNoncePlusOne));
        vm.label(address(_jbRulesets), "JBRulesets");

        // JBDirectory
        _jbDirectory = new JBDirectory(_jbPermissions, _jbProjects, _jbRulesets, _multisig);
        vm.label(address(_jbDirectory), "JBDirectory");

        // JBTokens
        _jbTokens = new JBTokens(_jbPermissions, _jbProjects, _jbDirectory, _jbRulesets);
        vm.label(address(_jbTokens), "JBTokens");

        // JBSplits
        _jbSplits = new JBSplits(_jbPermissions, _jbProjects, _jbDirectory);
        vm.label(address(_jbSplits), "JBSplits");

        _fundAccessConstraintsStore = new JBFundAccessLimits(_jbDirectory);
        vm.label(address(_fundAccessConstraintsStore), "JBFundAccessLimits");

        // JBController
        _jbController = new JBController(
            _jbPermissions, _jbProjects, _jbDirectory, _jbRulesets, _jbTokens, _jbSplits, _fundAccessConstraintsStore
        );
        vm.label(address(_jbController), "JBController");

        vm.prank(_multisig);
        _jbDirectory.setIsAllowedToSetFirstController(address(_jbController), true);

        // JBETHPaymentTerminalStore
        _jbPaymentTerminalStore = new JBTerminalStore(_jbDirectory, _jbRulesets, _jbPrices);
        vm.label(address(_jbPaymentTerminalStore), "JBSingleTokenPaymentTerminalStore");

        // AccessJBLib
        _accessJBLib = new AccessJBLib();

        // JBETHPaymentTerminal
        _jbETHPaymentTerminal = new JBMultiTerminal(
            _accessJBLib.ETH(),
            _jbPermissions,
            _jbProjects,
            _jbDirectory,
            _jbSplits,
            _jbPrices,
            address(_jbPaymentTerminalStore),
            _multisig
        );
        vm.label(address(_jbETHPaymentTerminal), "JBETHPaymentTerminal");

        // Deploy the delegate
        _delegate = new JBBuybackHook({
            _weth: weth,
            _factory: _uniswapFactory,
            _directory: IJBDirectory(address(_jbDirectory)),
            _controller: _jbController,
            _delegateId: bytes4(hex"69")
        });

        _data = JBRulesetData({
            duration: 6 days,
            weight: weight,
            decayRate: 0,
            hook: IJBRulesetApprovalHook(address(0))
        });

        _metadata = JBRulesetMetadata({
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
            dataHook: address(_delegate),
            metadata: 0
        });

        JBSplitGroup[] memory _groupedSplits = new JBSplitGroup[](1); // Default empty

        _fundAccessLimitGroup = JBFundAccessLimitGroup({
            terminal: _jbETHPaymentTerminal,
            token: jbLibraries().ETHToken(),
            distributionLimit: 2 ether,
            overflowAllowance: type(uint232).max,
            distributionLimitCurrency: 1, // Currency = ETH
            overflowAllowanceCurrency: 1
        });

        // Package up the ruleset configuration.
        JBRulesetConfig[] memory _rulesetConfigurations = new JBRulesetConfig[](1);
        _rulesetConfigurations[0].mustStartAtOrAfter = 0;
        _rulesetConfigurations[0].data = _data;
        _rulesetConfigurations[0].metadata = _metadata;
        _rulesetConfigurations[0].splitGroups = new JBSplitGroup[](0);
        _rulesetConfigurations[0].fundAccessLimitGroups = _fundAccessLimitGroup;

        JBTerminalConfig[] memory _terminalConfigurations = new JBTerminalConfig[](1);
        JBAccountingContextConfig[] memory _accountingContextConfigs = new JBAccountingContextConfig[](1);
        _accountingContextConfigs[0] =
            JBAccountingContextConfig({token: JBConstants.NATIVE_TOKEN, standard: JBTokenStandards.NATIVE});
        _terminalConfigurations[0] =
            JBTerminalConfig({terminal: _jbETHPaymentTerminal, accountingContextConfigs: _accountingContextConfigs});

        _projectId = _jbController.launchProjectFor({
            owner: _multisig,
            projectMetadata: "myIPFSHash",
            rulesetConfigurations: _rulesetConfigurations,
            terminalConfigurations: _terminalConfigurations, // Set terminals to receive fees.
            memo: ""
        });

        vm.prank(_multisig);
        _jbTokens.issueFor(_projectId, "jbx", "jbx");

        vm.prank(_multisig);
        pool = _delegate.setPoolFor(_projectId, fee, uint32(cardinality), twapDelta, address(weth));
    }
}
