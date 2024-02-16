// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "../lib/@looksrare/contracts-libs/contracts/interfaces/generic/IERC20.sol";
import {ReentrancyGuard} from "../lib/@looksrare/contracts-libs/contracts/ReentrancyGuard.sol";
import {Pausable} from "../lib/@looksrare/contracts-libs/contracts/Pausable.sol";

import {LowLevelWETH} from "../lib/@looksrare/contracts-libs/contracts/lowLevelCallers/LowLevelWETH.sol";
import {LowLevelERC20Transfer} from "../lib/@looksrare/contracts-libs/contracts/lowLevelCallers/LowLevelERC20Transfer.sol";

import {AccessControl} from "../lib/@openzeppelin/contracts/access/AccessControl.sol";

import {IEntropy} from "../lib/@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import "../lib/@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "../lib/@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import {ILudka} from "./interfaces/ILudka.sol";
import {IBlast} from "./interfaces/IBlast.sol";
import {Arrays} from "./libraries/Arrays.sol";

/**
 * @title Ludka
 * @notice This contract permissionlessly hosts Ludkas
 * @author luthreek
 */
contract Ludka is
    ILudka,
    AccessControl,
    LowLevelWETH,
    LowLevelERC20Transfer,
    ReentrancyGuard,
    Pausable
{
    using Arrays for uint256[];

    /**
     * @notice Operators are allowed to add/remove allowed ERC-20.
     */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /**
     * @notice The maximum protocol fee in basis points, which is 5%.
     */
    uint16 public constant MAXIMUM_PROTOCOL_FEE_BP = 500;
    /**
     * @notice the Blast contract for change Gas Mode to Claimable.
     */
    IBlast public constant BLAST =
        IBlast(0x4300000000000000000000000000000000000002);

    /**
     * @notice Wrapped Ether address.
     */
    address private immutable WETH;

    /**
     * @notice The PYTH Entropy.
     */
    IEntropy private immutable entropy;

    IPyth pyth;

    address private entropyProvider;

    /**
     * @notice The value of each entry in ETH.
     */
    uint256 public valuePerEntry;

    /**
     * @notice The duration of each round.
     */
    uint40 public roundDuration;

    /**
     * @notice The address of the protocol fee recipient.
     */
    address public protocolFeeRecipient;

    /**
     * @notice The protocol fee basis points.
     */
    uint16 public protocolFeeBp;

    /**
     * @notice Number of rounds that have been created.
     * @dev In this smart contract, roundId is an uint256 but its
     *      max value can only be 2^40 - 1. Realistically we will still
     *      not reach this number.
     */
    uint40 public roundsCount;

    /**
     * @notice The maximum number of participants per round.
     */
    uint40 public maximumNumberOfParticipantsPerRound;

    /**
     * @notice The maximum number of deposits per round.
     */
    uint40 public maximumNumberOfDepositsPerRound;

    /**
     * @notice It checks whether the currency is allowed.
     * @dev 0 is not allowed, 1 is allowed.
     */
    mapping(address => uint256) public isCurrencyAllowed;

    /**
     * @dev roundId => Round
     */
    mapping(uint256 => Round) public rounds;

    /**
     * @dev roundId => depositor => depositCount
     */
    mapping(uint256 => mapping(address => uint256)) public depositCount;

    /**
     * @dev Token/collection => round ID => price.
     */
    mapping(address => mapping(uint256 => uint256)) public prices;
    /**
     * @dev PYTH Entropy sequenceNumber => depositor.
     */
    mapping(uint64 => address) private requestedFlips;

    /**
     *  params The constructor params.
     */
    constructor(
        address owner,
        address operator,
        uint40 _maximumNumberOfDepositsPerRound,
        uint40 _maximumNumberOfParticipantsPerRound,
        uint40 _roundDuration,
        uint256 _valuePerEntry,
        address _protocolFeeRecipient,
        uint16 _protocolFeeBp,
        address _entropy,
        address _entropyProvider,
        address _pythContract,
        address _weth
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(OPERATOR_ROLE, operator);
        _updateRoundDuration(_roundDuration);
        _updateProtocolFeeRecipient(_protocolFeeRecipient);
        _updateProtocolFeeBp(_protocolFeeBp);
        _updateValuePerEntry(_valuePerEntry);
        _updateMaximumNumberOfDepositsPerRound(
            _maximumNumberOfDepositsPerRound
        );
        _updateMaximumNumberOfParticipantsPerRound(
            _maximumNumberOfParticipantsPerRound
        );
        WETH = _weth;
        entropy = IEntropy(_entropy);
        pyth = IPyth(_pythContract);
        entropyProvider = (_entropyProvider);
        BLAST.configureClaimableGas();
        _startRound({_roundsCount: 0});
    }

    /**
     * @inheritdoc ILudka
     */
    function cancelCurrentRoundAndDepositToTheNextRound(
        DepositCalldata[] calldata deposits,
        bytes32 userCommitment,
        bytes[] calldata pythUpdateData
    ) external payable nonReentrant whenNotPaused {
        uint256 roundId = roundsCount;
        _cancel(roundId);
        _deposit(
            _unsafeAdd(roundId, 1),
            deposits,
            userCommitment,
            pythUpdateData
        );
    }

    /**
     * @inheritdoc ILudka
     */
    function deposit(
        uint256 roundId,
        DepositCalldata[] calldata deposits,
        bytes32 userCommitment,
        bytes[] calldata pythUpdateData
    ) external payable nonReentrant whenNotPaused {
        _deposit(roundId, deposits, userCommitment, pythUpdateData);
    }

    /**
     * @inheritdoc ILudka
     */
    function getDeposits(
        uint256 roundId
    ) external view returns (Deposit[] memory) {
        return rounds[roundId].deposits;
    }

    function drawWinner(
        bytes32 userCommitment
    ) external nonReentrant whenNotPaused {
        uint256 roundId = roundsCount;
        Round storage round = rounds[roundId];

        _validateRoundStatus(round, RoundStatus.Open);

        if (block.timestamp < round.cutoffTime) {
            revert CutoffTimeNotReached();
        }

        if (round.numberOfParticipants < 2) {
            revert InsufficientParticipants();
        }

        _drawWinner(round, roundId, userCommitment);
    }

    function cancel() external nonReentrant whenNotPaused {
        _cancel({roundId: roundsCount});
    }

    /**
     * @inheritdoc ILudka
     */
    function cancelAfterRandomnessRequest()
        external
        nonReentrant
        whenNotPaused
    {
        uint256 roundId = roundsCount;
        Round storage round = rounds[roundId];

        _validateRoundStatus(round, RoundStatus.Drawing);

        if (block.timestamp < round.drawnAt + 1 days) {
            revert DrawExpirationTimeNotReached();
        }

        round.status = RoundStatus.Cancelled;

        emit RoundStatusUpdated(roundId, RoundStatus.Cancelled);

        _startRound({_roundsCount: roundId});
    }

    /**
     * @inheritdoc ILudka
     */
    function claimPrizes(
        ClaimPrizesCalldata[] calldata claimPrizesCalldata
    ) external payable nonReentrant whenNotPaused {
        TransferAccumulator memory transferAccumulator;
        uint256 ethAmount;
        uint256 protocolFeeOwed;

        for (uint256 i; i < claimPrizesCalldata.length; ) {
            ClaimPrizesCalldata
                calldata perRoundClaimPrizesCalldata = claimPrizesCalldata[i];

            Round storage round = rounds[perRoundClaimPrizesCalldata.roundId];

            _validateRoundStatus(round, RoundStatus.Drawn);

            if (msg.sender != round.winner) {
                revert NotWinner();
            }

            uint256[] calldata prizeIndices = perRoundClaimPrizesCalldata
                .prizeIndices;

            for (uint256 j; j < prizeIndices.length; ) {
                uint256 index = prizeIndices[j];
                if (index >= round.deposits.length) {
                    revert InvalidIndex();
                }

                Deposit storage prize = round.deposits[index];

                if (prize.withdrawn) {
                    revert AlreadyWithdrawn();
                }

                prize.withdrawn = true;

                TokenType tokenType = prize.tokenType;
                if (tokenType == TokenType.ETH) {
                    ethAmount += prize.tokenAmount;
                } else if (tokenType == TokenType.ERC20) {
                    address prizeAddress = prize.tokenAddress;
                    if (prizeAddress == transferAccumulator.tokenAddress) {
                        transferAccumulator.amount += prize.tokenAmount;
                    } else {
                        if (transferAccumulator.amount != 0) {
                            _executeERC20DirectTransfer(
                                transferAccumulator.tokenAddress,
                                msg.sender,
                                transferAccumulator.amount
                            );
                        }

                        transferAccumulator.tokenAddress = prizeAddress;
                        transferAccumulator.amount = prize.tokenAmount;
                    }
                }

                unchecked {
                    ++j;
                }
            }

            protocolFeeOwed += round.protocolFeeOwed;
            round.protocolFeeOwed = 0;

            emit PrizesClaimed(
                perRoundClaimPrizesCalldata.roundId,
                msg.sender,
                prizeIndices
            );

            unchecked {
                ++i;
            }
        }

        if (protocolFeeOwed != 0) {
            _transferETHAndWrapIfFailWithGasLimit(
                WETH,
                protocolFeeRecipient,
                protocolFeeOwed,
                gasleft()
            );

            protocolFeeOwed -= msg.value;
            if (protocolFeeOwed < ethAmount) {
                unchecked {
                    ethAmount -= protocolFeeOwed;
                }
                protocolFeeOwed = 0;
            } else {
                unchecked {
                    protocolFeeOwed -= ethAmount;
                }
                ethAmount = 0;
            }

            if (protocolFeeOwed != 0) {
                revert ProtocolFeeNotPaid();
            }
        }

        if (transferAccumulator.amount != 0) {
            _executeERC20DirectTransfer(
                transferAccumulator.tokenAddress,
                msg.sender,
                transferAccumulator.amount
            );
        }

        if (ethAmount != 0) {
            _transferETHAndWrapIfFailWithGasLimit(
                WETH,
                msg.sender,
                ethAmount,
                gasleft()
            );
        }
    }

    /**
     * @inheritdoc ILudka
     * @dev This function does not validate claimPrizesCalldata to not contain duplicate round IDs and prize indices.
     *      It is the responsibility of the caller to ensure that. Otherwise, the returned protocol fee owed will be incorrect.
     */
    function getClaimPrizesPaymentRequired(
        ClaimPrizesCalldata[] calldata claimPrizesCalldata
    ) external view returns (uint256 protocolFeeOwed) {
        uint256 ethAmount;

        for (uint256 i; i < claimPrizesCalldata.length; ) {
            ClaimPrizesCalldata
                calldata perRoundClaimPrizesCalldata = claimPrizesCalldata[i];
            Round storage round = rounds[perRoundClaimPrizesCalldata.roundId];

            _validateRoundStatus(round, RoundStatus.Drawn);

            uint256[] calldata prizeIndices = perRoundClaimPrizesCalldata
                .prizeIndices;
            uint256 numberOfPrizes = prizeIndices.length;
            uint256 prizesCount = round.deposits.length;

            for (uint256 j; j < numberOfPrizes; ) {
                uint256 index = prizeIndices[j];
                if (index >= prizesCount) {
                    revert InvalidIndex();
                }

                Deposit storage prize = round.deposits[index];
                if (prize.tokenType == TokenType.ETH) {
                    ethAmount += prize.tokenAmount;
                }

                unchecked {
                    ++j;
                }
            }

            protocolFeeOwed += round.protocolFeeOwed;

            unchecked {
                ++i;
            }
        }

        if (protocolFeeOwed < ethAmount) {
            protocolFeeOwed = 0;
        } else {
            unchecked {
                protocolFeeOwed -= ethAmount;
            }
        }
    }

    /**
     * @inheritdoc ILudka
     */
    function withdrawDeposits(
        uint256 roundId,
        uint256[] calldata depositIndices
    ) external nonReentrant whenNotPaused {
        Round storage round = rounds[roundId];

        _validateRoundStatus(round, RoundStatus.Cancelled);

        uint256 numberOfDeposits = depositIndices.length;
        uint256 depositsCount = round.deposits.length;
        uint256 ethAmount;

        for (uint256 i; i < numberOfDeposits; ) {
            uint256 index = depositIndices[i];
            if (index >= depositsCount) {
                revert InvalidIndex();
            }

            Deposit storage depositedToken = round.deposits[index];
            if (depositedToken.depositor != msg.sender) {
                revert NotDepositor();
            }

            if (depositedToken.withdrawn) {
                revert AlreadyWithdrawn();
            }

            depositedToken.withdrawn = true;

            TokenType tokenType = depositedToken.tokenType;
            if (tokenType == TokenType.ETH) {
                ethAmount += depositedToken.tokenAmount;
            } else if (tokenType == TokenType.ERC20) {
                _executeERC20DirectTransfer(
                    depositedToken.tokenAddress,
                    msg.sender,
                    depositedToken.tokenAmount
                );
            }

            unchecked {
                ++i;
            }
        }

        if (ethAmount != 0) {
            _transferETHAndWrapIfFailWithGasLimit(
                WETH,
                msg.sender,
                ethAmount,
                gasleft()
            );
        }

        emit DepositsWithdrawn(roundId, msg.sender, depositIndices);
    }

    /**
     * @inheritdoc ILudka
     */
    function togglePaused() external {
        _validateIsOwner();
        paused() ? _unpause() : _pause();
    }

    /**
     * @inheritdoc ILudka
     */
    function updateCurrenciesStatus(
        address[] calldata currencies,
        bool isAllowed
    ) external {
        _validateIsOperator();

        uint256 count = currencies.length;
        for (uint256 i; i < count; ) {
            isCurrencyAllowed[currencies[i]] = (isAllowed ? 1 : 0);
            unchecked {
                ++i;
            }
        }
        emit CurrenciesStatusUpdated(currencies, isAllowed);
    }

    /**
     * @inheritdoc ILudka
     */
    function updateRoundDuration(uint40 _roundDuration) external {
        _validateIsOwner();
        _updateRoundDuration(_roundDuration);
    }

    /**
     * @inheritdoc ILudka
     */
    function updateValuePerEntry(uint256 _valuePerEntry) external {
        _validateIsOwner();
        _updateValuePerEntry(_valuePerEntry);
    }

    /**
     * @inheritdoc ILudka
     */
    function updateProtocolFeeRecipient(
        address _protocolFeeRecipient
    ) external {
        _validateIsOwner();
        _updateProtocolFeeRecipient(_protocolFeeRecipient);
    }

    /**
     * @inheritdoc ILudka
     */
    function updateProtocolFeeBp(uint16 _protocolFeeBp) external {
        _validateIsOwner();
        _updateProtocolFeeBp(_protocolFeeBp);
    }

    /**
     * @inheritdoc ILudka
     */
    function updateMaximumNumberOfDepositsPerRound(
        uint40 _maximumNumberOfDepositsPerRound
    ) external {
        _validateIsOwner();
        _updateMaximumNumberOfDepositsPerRound(
            _maximumNumberOfDepositsPerRound
        );
    }

    /**
     * @inheritdoc ILudka
     */
    function updateMaximumNumberOfParticipantsPerRound(
        uint40 _maximumNumberOfParticipantsPerRound
    ) external {
        _validateIsOwner();
        _updateMaximumNumberOfParticipantsPerRound(
            _maximumNumberOfParticipantsPerRound
        );
    }

    /**
     * @inheritdoc ILudka
     */
    function updatePYTHOracle(address _PYTHOracle) external {
        _validateIsOwner();
        _updatePYTHOracle(_PYTHOracle);
    }

    /**
    IBlast
     */
    function claimMyContractsAllGas() external {
        _validateIsOwner();
        BLAST.claimAllGas(address(this), msg.sender);
    }

    /*     
    minClaimRateBips - 80% claim rate, that translates to 8000 Bips, 100% = 10000 Bips
      */
    function claimGasAtMinClaimRate(uint256 minClaimRateBips) external {
        _validateIsOwner();
        BLAST.claimGasAtMinClaimRate(
            address(this),
            msg.sender,
            minClaimRateBips
        );
    }

    function _validateIsOwner() private view {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotOwner();
        }
    }

    function _validateIsOperator() private view {
        if (!hasRole(OPERATOR_ROLE, msg.sender)) {
            revert NotOperator();
        }
    }

    /**
     * @param _roundDuration The duration of each round.
     */
    function _updateRoundDuration(uint40 _roundDuration) private {
        if (_roundDuration > 1 hours) {
            revert InvalidRoundDuration();
        }

        roundDuration = _roundDuration;
        emit RoundDurationUpdated(_roundDuration);
    }

    /**
     * @param _valuePerEntry The value of each entry in ETH.
     */
    function _updateValuePerEntry(uint256 _valuePerEntry) private {
        if (_valuePerEntry == 0) {
            revert InvalidValue();
        }
        valuePerEntry = _valuePerEntry;
        emit ValuePerEntryUpdated(_valuePerEntry);
    }

    /**
     * @param _protocolFeeRecipient The new protocol fee recipient address
     */
    function _updateProtocolFeeRecipient(
        address _protocolFeeRecipient
    ) private {
        if (_protocolFeeRecipient == address(0)) {
            revert InvalidValue();
        }
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    /**
     * @param _protocolFeeBp The new protocol fee in basis points
     */
    function _updateProtocolFeeBp(uint16 _protocolFeeBp) private {
        if (_protocolFeeBp > MAXIMUM_PROTOCOL_FEE_BP) {
            revert InvalidValue();
        }
        protocolFeeBp = _protocolFeeBp;
        emit ProtocolFeeBpUpdated(_protocolFeeBp);
    }

    /**
     * @param _maximumNumberOfDepositsPerRound The new maximum number of deposits per round
     */
    function _updateMaximumNumberOfDepositsPerRound(
        uint40 _maximumNumberOfDepositsPerRound
    ) private {
        maximumNumberOfDepositsPerRound = _maximumNumberOfDepositsPerRound;
        emit MaximumNumberOfDepositsPerRoundUpdated(
            _maximumNumberOfDepositsPerRound
        );
    }

    /**
     * @param _maximumNumberOfParticipantsPerRound The new maximum number of participants per round
     */
    function _updateMaximumNumberOfParticipantsPerRound(
        uint40 _maximumNumberOfParticipantsPerRound
    ) private {
        if (_maximumNumberOfParticipantsPerRound < 2) {
            revert InvalidValue();
        }
        maximumNumberOfParticipantsPerRound = _maximumNumberOfParticipantsPerRound;
        emit MaximumNumberOfParticipantsPerRoundUpdated(
            _maximumNumberOfParticipantsPerRound
        );
    }

    /**
     * @param _PYTHOracle The new PYTH oracle address
     */
    function _updatePYTHOracle(address _PYTHOracle) private {
        if (_PYTHOracle == address(0)) {
            revert InvalidValue();
        }
        pyth = IPyth(_PYTHOracle);
        emit PYTHOracleUpdated(_PYTHOracle);
    }

    /**
     * @param _roundsCount The current rounds count
     */
    function _startRound(
        uint256 _roundsCount
    ) private returns (uint256 roundId) {
        unchecked {
            roundId = _roundsCount + 1;
        }
        roundsCount = uint40(roundId);
        rounds[roundId].status = RoundStatus.Open;
        rounds[roundId].protocolFeeBp = protocolFeeBp;
        rounds[roundId].cutoffTime = uint40(block.timestamp) + roundDuration;
        rounds[roundId]
            .maximumNumberOfDeposits = maximumNumberOfDepositsPerRound;
        rounds[roundId]
            .maximumNumberOfParticipants = maximumNumberOfParticipantsPerRound;
        rounds[roundId].valuePerEntry = valuePerEntry;

        emit RoundStatusUpdated(roundId, RoundStatus.Open);
    }

    /**
     * @param round The open round.
     * @param roundId The open round ID.
     */
    function _drawWinner(
        Round storage round,
        uint256 roundId,
        bytes32 userCommitment
    ) private {
        round.status = RoundStatus.Drawing;
        round.drawnAt = uint40(block.timestamp);

        uint256 fee = entropy.getFee(entropyProvider);
        uint64 sequenceNumber = entropy.request{value: fee}(
            entropyProvider,
            userCommitment,
            true
        );
        requestedFlips[sequenceNumber] = msg.sender;
        emit RoundStatusUpdated(roundId, RoundStatus.Drawing);
    }

    /**
     * @param roundId The open round ID.
     * @param deposits The ERC-20 deposits to be made.
     */
    function _deposit(
        uint256 roundId,
        DepositCalldata[] calldata deposits,
        bytes32 userCommitment,
        bytes[] calldata priceUpdateData
    ) private {
        Round storage round = rounds[roundId];
        if (
            round.status != RoundStatus.Open ||
            block.timestamp >= round.cutoffTime
        ) {
            revert InvalidStatus();
        }

        uint256 userDepositCount = depositCount[roundId][msg.sender];
        if (userDepositCount == 0) {
            unchecked {
                ++round.numberOfParticipants;
            }
        }
        uint256 roundDepositCount = round.deposits.length;
        uint40 currentEntryIndex;
        uint256 totalEntriesCount;

        uint256 depositsCalldataLength = deposits.length;
        if (msg.value == 0) {
            if (depositsCalldataLength == 0) {
                revert ZeroDeposits();
            }
        } else {
            uint256 roundValuePerEntry = round.valuePerEntry;
            if (msg.value % roundValuePerEntry != 0) {
                revert InvalidValue();
            }
            uint256 entriesCount = msg.value / roundValuePerEntry;
            totalEntriesCount += entriesCount;

            currentEntryIndex = _getCurrentEntryIndexWithoutAccrual(
                round,
                roundDepositCount,
                entriesCount
            );

            round.deposits.push(
                Deposit({
                    tokenType: TokenType.ETH,
                    tokenAddress: address(0),
                    tokenAmount: msg.value,
                    depositor: msg.sender,
                    withdrawn: false,
                    currentEntryIndex: currentEntryIndex
                })
            );

            unchecked {
                roundDepositCount += 1;
            }
        }

        if (depositsCalldataLength != 0) {
            for (uint256 i; i < depositsCalldataLength; ) {
                DepositCalldata calldata singleDeposit = deposits[i];
                if (isCurrencyAllowed[singleDeposit.tokenAddress] != 1) {
                    revert InvalidCollection();
                }
                uint256 price = prices[singleDeposit.tokenAddress][roundId];
                if (singleDeposit.tokenType == TokenType.ERC20) {
                    if (price == 0) {
                        uint fee = pyth.getUpdateFee(priceUpdateData);
                        pyth.updatePriceFeeds{value: fee}(priceUpdateData);
                        bytes32 priceId = 0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b;
                        price = convertToUint(pyth.getPrice(priceId), 18);
                        prices[singleDeposit.tokenAddress][roundId] = price;
                    }

                    uint256[] memory amounts = singleDeposit.tokenAmounts;
                    if (amounts.length != 1) {
                        revert InvalidLength();
                    }

                    uint256 amount = amounts[0];

                    uint256 entriesCount = ((price * amount) /
                        (10 ** IERC20(singleDeposit.tokenAddress).decimals())) /
                        round.valuePerEntry;
                    if (entriesCount == 0) {
                        revert InvalidValue();
                    }

                    totalEntriesCount += entriesCount;

                    if (currentEntryIndex != 0) {
                        currentEntryIndex += uint40(entriesCount);
                    } else {
                        currentEntryIndex = _getCurrentEntryIndexWithoutAccrual(
                            round,
                            roundDepositCount,
                            entriesCount
                        );
                    }

                    round.deposits.push(
                        Deposit({
                            tokenType: TokenType.ERC20,
                            tokenAddress: singleDeposit.tokenAddress,
                            tokenAmount: amount,
                            depositor: msg.sender,
                            withdrawn: false,
                            currentEntryIndex: currentEntryIndex
                        })
                    );

                    unchecked {
                        roundDepositCount += 1;
                    }
                } else {
                    revert InvalidTokenType();
                }

                unchecked {
                    ++i;
                }
            }
        }
        {
            uint256 maximumNumberOfDeposits = round.maximumNumberOfDeposits;
            if (roundDepositCount > maximumNumberOfDeposits) {
                revert MaximumNumberOfDepositsReached();
            }

            uint256 numberOfParticipants = round.numberOfParticipants;

            if (
                numberOfParticipants == round.maximumNumberOfParticipants ||
                (numberOfParticipants > 1 &&
                    roundDepositCount == maximumNumberOfDeposits)
            ) {
                _drawWinner(round, roundId, userCommitment);
            }
        }

        unchecked {
            depositCount[roundId][msg.sender] = userDepositCount + 1;
        }

        emit Deposited(msg.sender, roundId, totalEntriesCount);
    }

    /**
     * @param roundId The ID of the round to be cancelled.
     */
    function _cancel(uint256 roundId) private {
        Round storage round = rounds[roundId];

        _validateRoundStatus(round, RoundStatus.Open);

        if (block.timestamp < round.cutoffTime) {
            revert CutoffTimeNotReached();
        }

        if (round.numberOfParticipants > 1) {
            revert RoundCannotBeClosed();
        }

        round.status = RoundStatus.Cancelled;

        emit RoundStatusUpdated(roundId, RoundStatus.Cancelled);

        _startRound({_roundsCount: roundId});
    }

    /**
     * param randomNumber The random number returned by PYTH
     */
    function fulfillRandomNumber(
        uint64 sequenceNumber,
        bytes32 userRandom,
        bytes32 providerRandom,
        uint256 roundId
    ) internal {
        if (requestedFlips[sequenceNumber] != msg.sender) {
            revert NotDepositor();
        }

        Round storage round = rounds[roundId];

        if (round.status == RoundStatus.Drawing) {
            round.status = RoundStatus.Drawn;
            bytes32 randomNumber = entropy.reveal(
                entropyProvider,
                sequenceNumber,
                userRandom,
                providerRandom
            );

            uint256 count = round.deposits.length;
            uint256[] memory currentEntryIndexArray = new uint256[](count);
            for (uint256 i; i < count; ) {
                currentEntryIndexArray[i] = uint256(
                    round.deposits[i].currentEntryIndex
                );
                unchecked {
                    ++i;
                }
            }

            uint256 currentEntryIndex = currentEntryIndexArray[
                _unsafeSubtract(count, 1)
            ];
            uint256 entriesSold = _unsafeAdd(currentEntryIndex, 1);
            uint256 winningEntry = uint256(randomNumber) % entriesSold;
            round.winner = round
                .deposits[currentEntryIndexArray.findUpperBound(winningEntry)]
                .depositor;
            round.protocolFeeOwed =
                (round.valuePerEntry * entriesSold * round.protocolFeeBp) /
                10_000;

            emit RoundStatusUpdated(roundId, RoundStatus.Drawn);

            _startRound({_roundsCount: roundId});
        }
    }

    /**
     * @param round The round to check the status of.
     * @param status The expected status of the round
     */
    function _validateRoundStatus(
        Round storage round,
        RoundStatus status
    ) private view {
        if (round.status != status) {
            revert InvalidStatus();
        }
    }

    /**
     * @param round The open round.
     * @param roundDepositCount The number of deposits in the round.
     * @param entriesCount The number of entries to be added.
     */
    function _getCurrentEntryIndexWithoutAccrual(
        Round storage round,
        uint256 roundDepositCount,
        uint256 entriesCount
    ) private view returns (uint40 currentEntryIndex) {
        if (roundDepositCount == 0) {
            currentEntryIndex = uint40(_unsafeSubtract(entriesCount, 1));
        } else {
            currentEntryIndex = uint40(
                round
                    .deposits[_unsafeSubtract(roundDepositCount, 1)]
                    .currentEntryIndex + entriesCount
            );
        }
    }

    /**
     *@param price - PYTH oracle price
     *@param targetDecimals - decimal ERC20 token
     */
    function convertToUint(
        PythStructs.Price memory price,
        uint8 targetDecimals
    ) private pure returns (uint256) {
        if (price.price < 0 || price.expo > 0 || price.expo < -255) {
            revert();
        }

        uint8 priceDecimals = uint8(uint32(-1 * price.expo));

        if (targetDecimals >= priceDecimals) {
            return
                uint(uint64(price.price)) *
                10 ** uint32(targetDecimals - priceDecimals);
        } else {
            return
                uint(uint64(price.price)) /
                10 ** uint32(priceDecimals - targetDecimals);
        }
    }

    /**
     * Unsafe math functions.
     */

    function _unsafeAdd(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            return a + b;
        }
    }

    function _unsafeSubtract(
        uint256 a,
        uint256 b
    ) private pure returns (uint256) {
        unchecked {
            return a - b;
        }
    }
}