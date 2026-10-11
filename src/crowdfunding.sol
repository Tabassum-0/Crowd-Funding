 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

 /**
  * @title Crowdfunding
  * @author Tabassum
  * 
  * This system 
 */

contract Crowdfunding {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    struct Campaign {
        address creator;
        uint256 goal;        
        uint256 deadline;    
        uint256 totalRaised; 
        bool withdrawn;
        string title;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MIN_DURATION = 1 days;
    uint256 public constant MAX_DURATION = 90 days;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    uint256 public campaignCount;
    mapping(uint256 => Campaign) private _campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributions;

    uint256 private _locked = 1;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CampaignCreated(
        uint256 indexed id, address indexed creator, string title, uint256 goal, uint256 deadline
    );
    event Contributed(uint256 indexed id, address indexed contributor, uint256 amount);
    event Withdrawn(uint256 indexed id, address indexed creator, uint256 amount);
    event Refunded(uint256 indexed id, address indexed contributor, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidGoal();
    error InvalidDuration();
    error CampaignNotFound();
    error CampaignEnded();
    error CampaignNotEnded();
    error ZeroContribution();
    error GoalNotReached();
    error GoalReached();
    error NotCreator();
    error AlreadyWithdrawn();
    error NothingToRefund();
    error TransferFailed();
    error Reentrancy();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier exists(uint256 id) {
        if (id >= campaignCount) revert CampaignNotFound();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                             EXTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Start a new campaign.
    /// @param title Human-readable campaign title.
    /// @param goal Funding goal in wei.
    /// @param duration Campaign length in seconds (1 to 90 days).
    function createCampaign(string calldata title, uint256 goal, uint256 duration)
        external
        returns (uint256 id)
    {
        if (goal == 0) revert InvalidGoal();
        if (duration < MIN_DURATION || duration > MAX_DURATION) revert InvalidDuration();

        id = campaignCount++;
        uint256 deadline = block.timestamp + duration;

        _campaigns[id] = Campaign({
            creator: msg.sender,
            goal: goal,
            deadline: deadline,
            totalRaised: 0,
            withdrawn: false,
            title: title
        });

        emit CampaignCreated(id, msg.sender, title, goal, deadline);
    }

    /// @notice Contribute ETH to an active campaign.
    function contribute(uint256 id) external payable exists(id) {
        Campaign storage c = _campaigns[id];
        if (block.timestamp >= c.deadline) revert CampaignEnded();
        if (msg.value == 0) revert ZeroContribution();

        c.totalRaised += msg.value;
        contributions[id][msg.sender] += msg.value;

        emit Contributed(id, msg.sender, msg.value);
    }

    /// @notice Creator claims funds after the deadline if the goal was met.
    function withdraw(uint256 id) external exists(id) nonReentrant {
        Campaign storage c = _campaigns[id];
        if (msg.sender != c.creator) revert NotCreator();
        if (block.timestamp < c.deadline) revert CampaignNotEnded();
        if (c.totalRaised < c.goal) revert GoalNotReached();
        if (c.withdrawn) revert AlreadyWithdrawn();

        c.withdrawn = true; // effects before interaction
        uint256 amount = c.totalRaised;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(id, msg.sender, amount);
    }

    /// @notice Contributors reclaim their ETH if the campaign missed its goal.
    function refund(uint256 id) external exists(id) nonReentrant {
        Campaign storage c = _campaigns[id];
        if (block.timestamp < c.deadline) revert CampaignNotEnded();
        if (c.totalRaised >= c.goal) revert GoalReached();

        uint256 amount = contributions[id][msg.sender];
        if (amount == 0) revert NothingToRefund();

        contributions[id][msg.sender] = 0; // effects before interaction

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Refunded(id, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    function getCampaign(uint256 id) external view exists(id) returns (Campaign memory) {
        return _campaigns[id];
    }

    function isSuccessful(uint256 id) external view exists(id) returns (bool) {
        Campaign storage c = _campaigns[id];
        return c.totalRaised >= c.goal;
    }
}
