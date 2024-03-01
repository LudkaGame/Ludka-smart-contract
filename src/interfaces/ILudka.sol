// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILudka {
    enum RoundStatus {
        None,
        Open,
        Drawing,
        Drawn,
        Cancelled
    }

    enum TokenType {
        ETH,
        ERC20
    }

    event CurrenciesStatusUpdated(address[] currencies, bool isAllowed);
    event Deposited(address depositor, uint256 roundId, uint256 entriesCount);
    event PYTHOracleUpdated(address PYTHOracle);
    event MaximumNumberOfDepositsPerRoundUpdated(uint40 maximumNumberOfDepositsPerRound);
    event MaximumNumberOfParticipantsPerRoundUpdated(uint40 maximumNumberOfParticipantsPerRound);
    event PrizesClaimed(uint256 roundId, address winner, uint256[] prizeIndices);
    event DepositsWithdrawn(uint256 roundId, address depositor, uint256[] depositIndices);
    event ProtocolFeeBpUpdated(uint16 protocolFeeBp);
    event ProtocolFeeRecipientUpdated(address protocolFeeRecipient);
    event RandomnessRequested(uint256 roundId, uint256 requestId);
    event RoundDurationUpdated(uint40 roundDuration);
    event RoundStatusUpdated(uint256 roundId, RoundStatus status);
    event ValuePerEntryUpdated(uint256 valuePerEntry);

    error AlreadyWithdrawn();
    error CutoffTimeNotReached();
    error DrawExpirationTimeNotReached();
    error InsufficientParticipants();
    error InvalidCollection();
    error InvalidCurrency();
    error InvalidIndex();
    error InvalidLength();
    error InvalidRoundDuration();
    error InvalidStatus();
    error InvalidTokenType();
    error InvalidValue();
    error MaximumNumberOfDepositsReached();
    error MessageIdInvalid();
    error NotOperator();
    error NotOwner();
    error NotWinner();
    error NotDepositor();
    error ProtocolFeeNotPaid();
    error RoundCannotBeClosed();
    error ZeroDeposits();

    /**
     * @param owner The owner of the contract.
     * @param operator The operator of the contract.
     * @param roundDuration The duration of each round.
     * @param valuePerEntry The value of each entry in ETH.
     * @param protocolFeeRecipient The protocol fee recipient.
     * @param protocolFeeBp The protocol fee basis points.
     * @param entropy PYTH entropy address
     * @param entropyProvider PYTH entropy provider
     * @param pythContract ERC20 on-chain oracle address
     * @param weth address WETH
     *
     */
    struct ConstructorCalldata {
        address owner;
        address operator;
        uint40 maximumNumberOfDepositsPerRound;
        uint40 maximumNumberOfParticipantsPerRound;
        uint40 roundDuration;
        uint256 valuePerEntry;
        address protocolFeeRecipient;
        uint16 protocolFeeBp;
        address entropy;
        address entropyProvider;
        address pythContract;
        address weth;
    }

    /**
     * @param id The id of the response.
     * @param payload The payload of the response.
     * @param timestamp The timestamp of the response.
     * @param signature The signature of the response.
     */
    struct DepositCalldata {
        TokenType tokenType;
        address tokenAddress;
        uint256[] tokenAmounts;
    }

    struct Round {
        RoundStatus status;
        address winner;
        uint40 cutoffTime;
        uint40 drawnAt;
        uint40 numberOfParticipants;
        uint40 maximumNumberOfDeposits;
        uint40 maximumNumberOfParticipants;
        uint16 protocolFeeBp;
        uint256 protocolFeeOwed;
        uint256 valuePerEntry;
        Deposit[] deposits;
    }

    struct Deposit {
        TokenType tokenType;
        address tokenAddress;
        uint256 tokenAmount;
        address depositor;
        bool withdrawn;
        uint40 currentEntryIndex;
    }

    /**
     * @param roundId The id of the round.
     * @param prizeIndices The indices of the prizes to be claimed.
     */
    struct ClaimPrizesCalldata {
        uint256 roundId;
        uint256[] prizeIndices;
    }

    /**
     * @notice This is used to accumulate the amount of tokens to be transferred.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens accumulated.
     */
    struct TransferAccumulator {
        address tokenAddress;
        uint256 amount;
    }

    function cancel() external;

    /**
     * @notice Cancels a round after randomness request if the randomness request
     *         does not arrive after a certain amount of time.
     *         Only callable by contract owner.
     */
    function cancelAfterRandomnessRequest() external;

    /**
     * @param claimPrizesCalldata The rounds and the indices for the rounds for the prizes to claim.
     */
    function claimPrizes(ClaimPrizesCalldata[] calldata claimPrizesCalldata) external payable;

    /**
     * @notice This function calculates the ETH payment required to claim the prizes for multiple rounds.
     * @param claimPrizesCalldata The rounds and the indices for the rounds for the prizes to claim.
     */
    function getClaimPrizesPaymentRequired(ClaimPrizesCalldata[] calldata claimPrizesCalldata)
        external
        view
        returns (uint256 protocolFeeOwed);

    /**
     * @notice This function allows withdrawal of deposits from a round if the round is cancelled
     * @param roundId The drawn round ID.
     * @param depositIndices The indices of the deposits to withdraw.
     */
    function withdrawDeposits(uint256 roundId, uint256[] calldata depositIndices) external;

    /**
     * @param roundId The open round ID.
     */
    function deposit(uint256 roundId) external payable;

    /**
     *
     */
    function cancelCurrentRoundAndDepositToTheNextRound() external payable;

    function drawWinner(bytes32 userRandom, bytes32 providerRandom) external;

    /**
     * @param roundId The round ID.
     */
    function getDeposits(uint256 roundId) external view returns (Deposit[] memory);

    /**
     * @notice This function allows the owner to pause/unpause the contract.
     */
    function togglePaused() external;

    /**
     * @notice This function allows the owner to update currency statuses (ETH, ERC-20).
     * @param currencies Currency addresses (address(0) for ETH)
     * @param isAllowed Whether the currencies should be allowed in the ludkas
     * @dev Only callable by owner.
     */
    function updateCurrenciesStatus(address[] calldata currencies, bool isAllowed) external;

    /**
     * @notice This function allows the owner to update the duration of each round.
     * @param _roundDuration The duration of each round.
     */
    function updateRoundDuration(uint40 _roundDuration) external;

    /**
     * @notice This function allows the owner to update the value of each entry in ETH.
     * @param _valuePerEntry The value of each entry in ETH.
     */
    function updateValuePerEntry(uint256 _valuePerEntry) external;

    /**
     * @notice This function allows the owner to update the protocol fee in basis points.
     * @param protocolFeeBp The protocol fee in basis points.
     */
    function updateProtocolFeeBp(uint16 protocolFeeBp) external;

    /**
     * @notice This function allows the owner to update the protocol fee recipient.
     * @param protocolFeeRecipient The protocol fee recipient.
     */
    function updateProtocolFeeRecipient(address protocolFeeRecipient) external;

    /**
     * @notice This function allows the owner to update the maximum number of participants per round.
     * @param _maximumNumberOfParticipantsPerRound The maximum number of participants per round.
     */
    function updateMaximumNumberOfParticipantsPerRound(uint40 _maximumNumberOfParticipantsPerRound) external;

    /**
     * @notice This function allows the owner to update the maximum number of deposits per round.
     * @param _maximumNumberOfDepositsPerRound The maximum number of deposits per round.
     */
    function updateMaximumNumberOfDepositsPerRound(uint40 _maximumNumberOfDepositsPerRound) external;

    /**
     * @notice This function allows the owner to update ERC20 oracle's address.
     * @param PYTHOracle ERC20 oracle address.
     */
    function updatePYTHOracle(address PYTHOracle) external;
}
