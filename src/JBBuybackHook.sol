// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {mulDiv} from "lib/prb-math/src/Common.sol";
import {TickMath} from "lib/v3-core/contracts/libraries/TickMath.sol";
import {OracleLibrary} from "lib/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IJBTerminal} from "lib/juice-contracts-v4/src/interfaces/terminal/IJBTerminal.sol";
import {IJBMultiTerminal} from "lib/juice-contracts-v4/src/interfaces/terminal/IJBMultiTerminal.sol";
import {JBAfterPayRecordedContext} from "lib/juice-contracts-v4/src/structs/JBAfterPayRecordedContext.sol";
import {JBPermissioned} from "lib/juice-contracts-v4/src/abstract/JBPermissioned.sol";
import {IJBDirectory} from "lib/juice-contracts-v4/src/interfaces/IJBDirectory.sol";
import {IJBController} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBProjects} from "lib/juice-contracts-v4/src/interfaces/IJBController.sol";
import {IJBPermissioned} from "lib/juice-contracts-v4/src/interfaces/IJBPermissioned.sol";
import {IJBRulesetDataHook} from "lib/juice-contracts-v4/src/interfaces/IJBRulesetDataHook.sol";
import {IJBPayHook} from "lib/juice-contracts-v4/src/interfaces/IJBPayHook.sol";
import {JBPayHookSpecification} from "lib/juice-contracts-v4/src/structs/JBPayHookSpecification.sol";
import {JBBeforePayRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforePayRecordedContext.sol";
import {JBBeforeRedeemRecordedContext} from "lib/juice-contracts-v4/src/structs/JBBeforeRedeemRecordedContext.sol";
import {JBRedeemHookSpecification} from "lib/juice-contracts-v4/src/structs/JBRedeemHookSpecification.sol";
import {JBConstants} from "lib/juice-contracts-v4/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "lib/juice-contracts-v4/src/libraries/JBMetadataResolver.sol";
import {JBBuybackHookPermissionIds} from "./libraries/JBBuybackHookPermissionIds.sol";
import {IJBBuybackHook} from "./interfaces/IJBBuybackHook.sol";
import {IWETH9} from "./interfaces/external/IWETH9.sol";

/// @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
/// @notice The buyback hook allows beneficiaries of a payment to a project to either:
/// - Get tokens by paying the project through its terminal OR
/// - Buy tokens from the configured Uniswap v3 pool.
/// Depending on which route would yield more tokens for the beneficiary. The project's reserved rate applies to either route.
/// @dev Compatible with any `JBTerminal` and any project token that can be pooled on Uniswap v3.
contract JBBuybackHook is ERC165, JBPermissioned, IJBBuybackHook {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error SpecifiedSlippageExceeded();
    error InsufficientPayAmount();
    error NoProjectToken();
    error PoolAlreadySet();
    error InvalidTwapSlippageTolerance();
    error InvalidTwapWindow();
    error Unauthorized();

    //*********************************************************************//
    // --------------------- internal stored properties ------------------ //
    //*********************************************************************//

    /// @notice The TWAP parameters used for the given project when the payer does not specify a quote.
    /// See the README for further information.
    /// @dev This includes the TWAP slippage tolerance and TWAP window, packed into a `uint256`.
    /// @custom:param projectId The ID of the project to get the twap parameters for.
    mapping(uint256 projectId => uint256) internal twapParamsOf;

    //*********************************************************************//
    // --------------------- public constant properties ------------------ //
    //*********************************************************************//

    /// @notice The denominator used when calculating TWAP slippage percent values.
    uint256 public constant TWAP_SLIPPAGE_DENOMINATOR = 10_000;

    /// @notice Projects cannot specify a TWAP slippage tolerance smaller than this constant (out of `MAX_SLIPPAGE`).
    /// @dev This prevents TWAP slippage tolerances so low that the swap always reverts to default behavior unless a quote is specified in the payment metadata.
    uint256 public constant MIN_TWAP_SLIPPAGE_TOLERANCE = 100;

    /// @notice Projects cannot specify a TWAP slippage tolerance larger than this constant (out of `MAX_SLIPPAGE`).
    /// @dev This prevents TWAP slippage tolerances so high that they would result in highly unfavorable trade conditions for the payer unless a quote was specified in the payment metadata.
    uint256 public constant MAX_TWAP_SLIPPAGE_TOLERANCE = 9000;

    /// @notice Projects cannot specify a TWAP window shorter than this constant.
    /// @dev This serves to avoid  extremely short TWAP windows that could be manipulated or subject to high volatility.
    uint256 public constant MIN_TWAP_WINDOW = 2 minutes;

    /// @notice Projects cannot specify a TWAP window longer than this constant.
    /// @dev This serves to avoid excessively long TWAP windows that could lead to outdated pricing information and higher gas costs due to increased computational requirements.
    uint256 public constant MAX_TWAP_WINDOW = 2 days;

    //*********************************************************************//
    // -------------------- public immutable properties ------------------ //
    //*********************************************************************//

    /// @notice The address of the Uniswap v3 factory. Used to calculate pool addresses.
    address public immutable UNISWAP_V3_FACTORY;

    /// @notice The directory of terminals and controllers.
    IJBDirectory public immutable DIRECTORY;

    /// @notice The controller used to mint and burn tokens.
    IJBController public immutable CONTROLLER;

    /// @notice The project registry.
    IJBProjects public immutable PROJECTS;

    /// @notice The wETH contract.
    IWETH9 public immutable WETH;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    /// @notice The Uniswap pool where a given project's token and terminal token pair are traded.
    /// @custom:param projectId The ID of the project whose token is traded in the pool.
    /// @custom:param terminalToken The address of the terminal token that the project accepts for payments (and is traded in the pool).
    mapping(uint256 projectId => mapping(address terminalToken => IUniswapV3Pool)) public poolOf;

    /// @notice The address of each project's token.
    /// @custom:param projectId The ID of the project the token belongs to.
    mapping(uint256 projectId => address) public projectTokenOf;

    //*********************************************************************//
    // ------------------------- external views -------------------------- //
    //*********************************************************************//

    /// @notice Required by the `IJBRulesetDataHook` interfaces. Return false to not leak any permissions.
    function hasMintPermissionFor(uint256, address) external pure returns (bool) {
        return false;
    } // TODO: I think this can be removed.

    /// @notice The `IJBRulesetDataHook` implementation which determines whether tokens should be minted from the project or bought from the pool.
    /// @param context Payment context passed to the data hook by `terminalStore.recordPaymentFrom(...)`.
    /// `context.metadata` can specify a Uniswap quote and specify how much of the payment should be used to swap.
    /// If `context.metadata` does not specify a quote, one will be calculated based on the TWAP.
    /// If `context.metadata` does not specify how much of the payment should be used, the hook uses the full amount paid in.
    /// @return weight The weight to use. If tokens are being minted from the project, this is the original weight.
    /// If tokens are being bought from the pool, the weight is 0.
    /// If tokens are being minted AND bought from the pool, this weight is adjusted to take both into account.
    /// @return hookSpecifications Specifications containing pay hooks, as well as the amount and metadata to send to them. Fulfilled by the terminal.
    /// If tokens are only being minted, `hookSpecifications` will be empty.
    function beforePayRecordedWith(JBBeforePayRecordedContext calldata context)
        external
        view
        override
        returns (uint256 weight, JBPayHookSpecification[] memory hookSpecifications)
    {
        // Keep a reference to the amount paid in.
        uint256 totalPaid = context.amount.value;

        // Keep a reference to the weight.
        weight = context.weight;

        // Keep a reference to the minimum number of tokens expected from the swap.
        uint256 minimumSwapAmountOut;

        // Keep a reference to the amount to be used to swap (out of `totalPaid`).
        uint256 amountToSwapWith;

        // Keep a reference to a flag indicating whether a quote was specified in the payment metadata.
        bool quoteExists;

        // Scoped section to prevent stack too deep.
        {
            bytes memory metadata;

            // The metadata ID is the first 4 bytes of this contract's address.
            bytes4 metadataId = bytes4(bytes20(address(this)));

            // Unpack the quote specified by the payer/client (typically from the pool).
            (quoteExists, metadata) = JBMetadataResolver.getDataFor(metadataId, context.metadata);
            if (quoteExists) (amountToSwapWith, minimumSwapAmountOut) = abi.decode(metadata, (uint256, uint256));
        }

        // If the payer/client did not specify an amount to use towards the swap, use the `totalPaid`.
        if (amountToSwapWith == 0) amountToSwapWith = totalPaid;

        // Calculate how many tokens would be minted by a direct payment to the project.
        // `tokenCountWithoutHook` is a fixed point number with 18 decimals.
        uint256 tokenCountWithoutHook = mulDiv(amountToSwapWith, weight, 10 ** context.amount.decimals);

        // Keep a reference to the project's token.
        address projectToken = projectTokenOf[context.projectId];

        // Keep a reference to the token being used by the terminal that is calling this hook. Default to wETH if the terminal uses the native token.
        address terminalToken = context.amount.token == JBConstants.NATIVE_TOKEN ? address(WETH) : context.amount.token;

        // If a minimum amount of tokens to swap for wasn't specified by the player/client, calculate a minimum based on the TWAP.
        if (minimumSwapAmountOut == 0) {
            minimumSwapAmountOut = _getQuote(context.projectId, projectToken, amountToSwapWith, terminalToken);
        }

        // If the minimum amount of tokens from the swap exceeds the amount that paying the project directly would yield, swap.
        if (tokenCountWithoutHook < minimumSwapAmountOut) {
            // If the amount to swap with is greater than the actual amount paid in, revert.
            if (amountToSwapWith > totalPaid) revert InsufficientPayAmount();

            // Keep a reference to a flag indicating whether the Uniswap pool will reference the project token first in the pair.
            bool projectTokenIs0 = address(projectToken) < terminalToken;

            // Specify this hook as the one to use, the amount to swap with, and metadata which allows the swap to be executed.
            hookSpecifications = new JBPayHookSpecification[](1);
            hookSpecifications[0] = JBPayHookSpecification({
                hook: IJBPayHook(this),
                amount: amountToSwapWith,
                metadata: abi.encode(
                    quoteExists,
                    projectTokenIs0,
                    totalPaid == amountToSwapWith ? 0 : totalPaid - amountToSwapWith,
                    minimumSwapAmountOut
                    )
            });

            // All the minting will be done in `afterPayRecordedWith`. Return a weight of 0 to any additional minting from the terminal.
            return (0, hookSpecifications);
        }
    }

    /// @notice Get the TWAP window for a given project ID.
    /// @dev The "TWAP window" is the period over which the TWAP is computed.
    /// @param  projectId The ID of the project which the TWAP window applies to.
    /// @return secondsAgo The TWAP window in seconds.
    function twapWindowOf(uint256 projectId) external view returns (uint32) {
        return uint32(twapParamsOf[projectId]);
    }

    /// @notice Get the TWAP slippage tolerance for a given project ID.
    /// @dev The "TWAP slippage tolerance" is the maximum negative spread between the TWAP and the expected return from a swap.
    /// If the expected return unfavourably exceeds the TWAP slippage tolerance, the swap will revert.
    /// @param  projectId The ID of the project which the TWAP slippage tolerance applies to.
    /// @return tolerance The maximum slippage allowed relative to the TWAP, as a percent out of `TWAP_SLIPPAGE_DENOMINATOR`.
    function twapSlippageToleranceOf(uint256 projectId) external view returns (uint256) {
        return twapParamsOf[projectId] >> 128;
    }

    /// @notice To fulfill the `IJBRulesetDataHook` interface.
    /// @dev Pass redeem context back to the terminal without changes.
    /// @param context The redeem context passed in by the terminal.
    function beforeRedeemRecordedWith(JBBeforeRedeemRecordedContext calldata context)
        external
        pure
        override
        returns (uint256, JBRedeemHookSpecification[] memory hookSpecifications)
    {
        return (context.reclaimAmount.value, hookSpecifications);
    }

    //*********************************************************************//
    // -------------------------- public views --------------------------- //
    //*********************************************************************//

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IJBRulesetDataHook).interfaceId || interfaceId == type(IJBPayHook).interfaceId
            || interfaceId == type(IJBBuybackHook).interfaceId || super.supportsInterface(interfaceId);
    }

    //*********************************************************************//
    // ---------------------------- constructor -------------------------- //
    //*********************************************************************//

    /// @param weth The WETH contract.
    /// @param factory The address of the Uniswap v3 factory. Used to calculate pool addresses.
    /// @param directory The directory of terminals and controllers.
    /// @param controller The controller used to mint and burn tokens.
    constructor(
        IWETH9 weth,
        address factory,
        IJBDirectory directory,
        IJBController controller
    )
        JBPermissioned(IJBPermissioned(address(controller)).PERMISSIONS())
    {
        WETH = weth;
        DIRECTORY = directory;
        CONTROLLER = controller;
        UNISWAP_V3_FACTORY = factory;
        PROJECTS = controller.PROJECTS();
    }

    //*********************************************************************//
    // ---------------------- external transactions ---------------------- //
    //*********************************************************************//

    /// @notice Hooks used to swap a provided amount to the beneficiary, using any leftover amount to mint.
    /// @dev This hook is called only if the quote for the swap is bigger than the quote when minting.
    /// If the swap reverts (slippage, liquidity, etc), the delegate will then mint the same amount of token as if the
    /// delegate was not used.
    /// @param context The hook context passed by the terminal.
    function afterPayRecordedWith(JBAfterPayRecordedContext calldata context) external payable override {
        // Make sure only a payment terminal belonging to the project can access this functionality.
        if (!DIRECTORY.isTerminalOf(context.projectId, IJBTerminal(msg.sender))) {
            revert Unauthorized();
        }

        // Parse the metadata passed in from the data source.
        (bool quoteExists, bool projectTokenIs0, uint256 amountToMintWith, uint256 minimumSwapAmountOut) =
            abi.decode(context.hookMetadata, (bool, bool, uint256, uint256));

        // Get a reference to the amount of tokens that was swapped for.
        uint256 exactSwapAmountOut = _swap(context, projectTokenIs0);

        // Make sure the slippage is tolerable if passed in via an explicit quote.
        if (quoteExists && exactSwapAmountOut < minimumSwapAmountOut) revert SpecifiedSlippageExceeded();

        // Get a reference to any amount of tokens paid in remaining in this contract.
        uint256 terminalTokenInThisContract = context.forwardedAmount.token == JBConstants.NATIVE_TOKEN
            ? address(this).balance
            : IERC20(context.forwardedAmount.token).balanceOf(address(this));

        // Use any leftover amount of tokens paid in remaining to mint.
        // Keep a reference to the number of tokens being minted.
        uint256 partialMintTokenCount;
        if (terminalTokenInThisContract != 0) {
            partialMintTokenCount = mulDiv(terminalTokenInThisContract, context.weight, 10 ** context.amount.decimals);

            // If the token paid in wasn't ETH, give the terminal permission to pull them back into its balance.
            if (context.forwardedAmount.token != JBConstants.NATIVE_TOKEN) {
                IERC20(context.forwardedAmount.token).approve(msg.sender, terminalTokenInThisContract);
            }

            // Keep a reference to the amount being paid.
            uint256 payValue =
                context.forwardedAmount.token == JBConstants.NATIVE_TOKEN ? terminalTokenInThisContract : 0;

            // Add the paid amount back to the project's terminal balance.
            IJBMultiTerminal(msg.sender).addToBalanceOf{value: payValue}({
                projectId: context.projectId,
                token: context.forwardedAmount.token,
                amount: terminalTokenInThisContract,
                shouldReturnHeldFees: false,
                memo: "",
                metadata: bytes("")
            });

            emit Mint(context.projectId, terminalTokenInThisContract, partialMintTokenCount, msg.sender);
        }

        // Add amount to mint to leftover mint amount (avoiding stack too deep here)
        partialMintTokenCount += mulDiv(amountToMintWith, context.weight, 10 ** context.amount.decimals);

        // Mint the whole amount of tokens again together with the (optional partial mint), such that the correct
        // portion of reserved tokens get taken into account.
        CONTROLLER.mintTokensOf({
            projectId: context.projectId,
            tokenCount: exactSwapAmountOut + partialMintTokenCount,
            beneficiary: address(context.beneficiary),
            memo: "",
            useReservedRate: true
        });
    }

    /// @notice The Uniswap V3 pool callback where the token transfer is expected to happen.
    /// @param amount0Delta The amount of token 0 being used for the swap.
    /// @param amount1Delta The amount of token 1 being used for the swap.
    /// @param data Data passed in by the swap operation.
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Unpack the data passed in through the swap hook.
        (uint256 projectId, address terminalToken) = abi.decode(data, (uint256, address));

        // Get the terminal token, using WETH if the token paid in is ETH.
        address terminalTokenWithWETH = terminalToken == JBConstants.NATIVE_TOKEN ? address(WETH) : terminalToken;

        // Make sure this call is being made from within the swap execution.
        if (msg.sender != address(poolOf[projectId][terminalTokenWithWETH])) revert Unauthorized();

        // Keep a reference to the amount of tokens that should be sent to fulfill the swap (the positive delta)
        uint256 amountToSendToPool = amount0Delta < 0 ? uint256(amount1Delta) : uint256(amount0Delta);

        // Wrap ETH into WETH if relevant (do not rely on ETH delegate balance to support pure WETH terminals)
        if (terminalToken == JBConstants.NATIVE_TOKEN) WETH.deposit{value: amountToSendToPool}();

        // Transfer the token to the pool.
        IERC20(terminalTokenWithWETH).transfer(msg.sender, amountToSendToPool);
    }

    /// @notice Add a pool for a given project. This pool the becomes the default for a given token project <-->
    /// terminal token pair.
    /// @dev Uses create2 for callback auth and allows adding a pool not deployed yet.
    /// This can be called by the project owner or an address having the SET_POOL permission in JBPermissions
    /// @param projectId The ID of the project having its pool set.
    /// @param fee The fee that is used in the pool being set.
    /// @param twapWindow The period over which the TWAP is computed.
    /// @param twapSlippageTolerance The maximum deviation allowed between amount received and TWAP.
    /// @param terminalToken The terminal token that payments are made in.
    /// @return newPool The pool that was created.
    function setPoolFor(
        uint256 projectId,
        uint24 fee,
        uint32 twapWindow,
        uint256 twapSlippageTolerance,
        address terminalToken
    )
        external
        returns (IUniswapV3Pool newPool)
    {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBBuybackHookPermissionIds.CHANGE_POOL
        });

        // Make sure the provided delta is within sane bounds.
        if (twapSlippageTolerance < MIN_TWAP_SLIPPAGE_TOLERANCE || twapSlippageTolerance > MAX_TWAP_SLIPPAGE_TOLERANCE)
        {
            revert InvalidTwapSlippageTolerance();
        }

        // Make sure the provided period is within sane bounds.
        if (twapWindow < MIN_TWAP_WINDOW || twapWindow > MAX_TWAP_WINDOW) revert InvalidTwapWindow();

        // Keep a reference to the project's token.
        address projectToken = address(CONTROLLER.TOKENS().tokenOf(projectId));

        // Make sure the project has issued a token.
        if (projectToken == address(0)) revert NoProjectToken();

        // If the terminal token specified in ETH, use WETH instead.
        if (terminalToken == JBConstants.NATIVE_TOKEN) terminalToken = address(WETH);

        // Keep a reference to a flag indicating if the pool will reference the project token as the first in the pair.
        bool projectTokenIs0 = address(projectToken) < terminalToken;

        // Compute the corresponding pool's address, which is a function of both tokens and the specified fee.
        newPool = IUniswapV3Pool(
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                UNISWAP_V3_FACTORY,
                                keccak256(
                                    abi.encode(
                                        projectTokenIs0 ? projectToken : terminalToken,
                                        projectTokenIs0 ? terminalToken : projectToken,
                                        fee
                                    )
                                ),
                                // POOL_INIT_CODE_HASH from
                                // https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/PoolAddress.sol
                                bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54)
                            )
                        )
                    )
                )
            )
        );

        // Make sure this pool has yet to be specified in this delegate.
        if (poolOf[projectId][terminalToken] == newPool) revert PoolAlreadySet();

        // Store the pool.
        poolOf[projectId][terminalToken] = newPool;

        // Store the twap period and max slipage.
        twapParamsOf[projectId] = twapSlippageTolerance << 128 | twapWindow;
        projectTokenOf[projectId] = address(projectToken);

        emit TwapWindowChanged(projectId, 0, twapWindow, msg.sender);
        emit TwapSlippageToleranceChanged(projectId, 0, twapSlippageTolerance, msg.sender);
        emit PoolAdded(projectId, terminalToken, address(newPool), msg.sender);
    }

    /// @notice Increase the period over which the TWAP is computed.
    /// @dev This can be called by the project owner or an address having the SET_TWAP_PERIOD permission in
    /// JBPermissions.
    /// @param projectId The ID for which the new value applies.
    /// @param newWindow The new TWAP period.
    function setTwapWindowOf(uint256 projectId, uint32 newWindow) external {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBBuybackHookPermissionIds.SET_POOL_PARAMS
        });

        // Make sure the provided period is within sane bounds.
        if (newWindow < MIN_TWAP_WINDOW || newWindow > MAX_TWAP_WINDOW) {
            revert InvalidTwapWindow();
        }

        // Keep a reference to the currently stored TWAP params.
        uint256 twapParams = twapParamsOf[projectId];

        // Keep a reference to the old window value.
        uint256 oldWindow = uint128(twapParams);

        // Store the new packed value of the TWAP params.
        twapParamsOf[projectId] = uint256(newWindow) | ((twapParams >> 128) << 128);

        emit TwapWindowChanged(projectId, oldWindow, newWindow, msg.sender);
    }

    /// @notice Set the maximum deviation allowed between amount received and TWAP.
    /// @dev This can be called by the project owner or an address having the SET_POOL permission in JBPermissions.
    /// @param projectId The ID for which the new value applies.
    /// @param newSlippageTolerance the new delta, out of TWAP_SLIPPAGE_DENOMINATOR.
    function setTwapSlippageToleranceOf(uint256 projectId, uint256 newSlippageTolerance) external {
        // Enforce permissions.
        _requirePermissionFrom({
            account: PROJECTS.ownerOf(projectId),
            projectId: projectId,
            permissionId: JBBuybackHookPermissionIds.SET_POOL_PARAMS
        });

        // Make sure the provided delta is within sane bounds.
        if (newSlippageTolerance < MIN_TWAP_SLIPPAGE_TOLERANCE || newSlippageTolerance > MAX_TWAP_SLIPPAGE_TOLERANCE) {
            revert InvalidTwapSlippageTolerance();
        }

        // Keep a reference to the currently stored TWAP params.
        uint256 twapParams = twapParamsOf[projectId];

        // Keep a reference to the old slippage value.
        uint256 oldSlippageTolerance = twapParams >> 128;

        // Store the new packed value of the TWAP params.
        twapParamsOf[projectId] = newSlippageTolerance << 128 | ((twapParams << 128) >> 128);

        emit TwapSlippageToleranceChanged(
            projectId, oldSlippageTolerance, newSlippageTolerance, msg.sender
        );
    }

    //*********************************************************************//
    // ---------------------- internal functions ------------------------- //
    //*********************************************************************//

    /// @notice Get a quote based on TWAP over a secondsAgo period, taking into account a twapDelta max deviation.
    /// @param projectId The ID of the project for which the swap is being made.
    /// @param projectToken The project's token being swapped for.
    /// @param amountIn The amount being used to swap.
    /// @param terminalToken The token paid in being used to swap.
    /// @return amountOut the minimum amount received according to the TWAP.
    function _getQuote(
        uint256 projectId,
        address projectToken,
        uint256 amountIn,
        address terminalToken
    )
        internal
        view
        returns (uint256 amountOut)
    {
        // Get a reference to the pool that'll be used to make the swap.
        IUniswapV3Pool pool = poolOf[projectId][address(terminalToken)];

        // Make sure the pool exists.
        try pool.slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool unlocked) {
            // If the pool hasn't been initialized, return an empty quote.
            if (!unlocked) return 0;
        } catch {
            // If the address is invalid or if the pool has not yet been deployed, return an empty quote.
            return 0;
        }

        // Unpack the TWAP params and get a reference to the period and slippage.
        uint256 twapParams = twapParamsOf[projectId];
        uint32 quotePeriod = uint32(twapParams);
        uint256 maxDelta = twapParams >> 128;

        // Keep a reference to the TWAP tick.
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(address(pool), quotePeriod);

        // Get a quote based on this TWAP tick.
        amountOut = OracleLibrary.getQuoteAtTick({
            tick: arithmeticMeanTick,
            baseAmount: uint128(amountIn),
            baseToken: terminalToken,
            quoteToken: address(projectToken)
        });

        // Return the lowest TWAP tolerable.
        amountOut -= (amountOut * maxDelta) / TWAP_SLIPPAGE_DENOMINATOR;
    }

    /// @notice Swap the terminal token to receive the project token.
    /// @param data The afterPayRecordedContext passed by the terminal.
    /// @param projectTokenIs0 A flag indicating if the pool will reference the project token as the first in the pair.
    /// @return amountReceived The amount of tokens received from the swap.
    function _swap(
        JBAfterPayRecordedContext calldata data,
        bool projectTokenIs0
    )
        internal
        returns (uint256 amountReceived)
    {
        // The amount of tokens that are being used with which to make the swap.
        uint256 amountToSwapWith = data.forwardedAmount.value;

        // Get the terminal token, using WETH if the token paid in is ETH.
        address terminalTokenWithWETH =
            data.forwardedAmount.token == JBConstants.NATIVE_TOKEN ? address(WETH) : data.forwardedAmount.token;

        // Get a reference to the pool that'll be used to make the swap.
        IUniswapV3Pool pool = poolOf[data.projectId][terminalTokenWithWETH];

        // Try swapping.
        try pool.swap({
            recipient: address(this),
            zeroForOne: !projectTokenIs0,
            amountSpecified: int256(amountToSwapWith),
            sqrtPriceLimitX96: projectTokenIs0 ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1,
            data: abi.encode(data.projectId, data.forwardedAmount.token)
        }) returns (int256 amount0, int256 amount1) {
            // If the swap succeded, take note of the amount of tokens received. This will return as negative since it
            // is an exact input.
            amountReceived = uint256(-(projectTokenIs0 ? amount0 : amount1));
        } catch {
            // If the swap failed, return.
            return 0;
        }

        // Burn the whole amount received.
        CONTROLLER.burnTokensOf({holder: address(this), projectId: data.projectId, tokenCount: amountReceived, memo: ""});

        // We return the amount we received/burned and we will mint them to the user later

        emit Swap(data.projectId, amountToSwapWith, pool, amountReceived, msg.sender);
    }
}
