// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";

contract RefundAttacker {
    Crowdfunding public immutable c;
    uint256 public id;
    uint256 public reentries;

    constructor(Crowdfunding _c) {
        c = _c;
    }

    function contribute(uint256 _id) external payable {
        id = _id;
        c.contribute{value: msg.value}(_id);
    }

    function attack() external {
        c.refund(id);
    }

    receive() external payable {
        if (reentries < 3) {
            reentries++;
            try c.refund(id) {} catch {}
        }
    }
}

contract CrowdfundingTest is Test {
    Crowdfunding cf;

    address creator = makeAddr("creator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant GOAL = 10 ether;
    uint256 constant DURATION = 30 days;

    event CampaignCreated(uint256 indexed id, address indexed creator, string title, uint256 goal, uint256 deadline);
    event Contributed(uint256 indexed id, address indexed contributor, uint256 amount);

    function setUp() public {
        cf = new Crowdfunding();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _create() internal returns (uint256 id) {
        vm.prank(creator);
        id = cf.createCampaign("My Project", GOAL, DURATION);
    }

    /*---------------------------- create ----------------------------*/

    function test_CreateCampaign() public {
        vm.expectEmit(true, true, false, true);
        emit CampaignCreated(0, creator, "My Project", GOAL, block.timestamp + DURATION);

        uint256 id = _create();
        Crowdfunding.Campaign memory c = cf.getCampaign(id);

        assertEq(id, 0);
        assertEq(c.creator, creator);
        assertEq(c.goal, GOAL);
        assertEq(c.deadline, block.timestamp + DURATION);
        assertEq(c.totalRaised, 0);
        assertFalse(c.withdrawn);
        assertEq(cf.campaignCount(), 1);
    }

    function test_CreateRevertsOnZeroGoal() public {
        vm.expectRevert(Crowdfunding.InvalidGoal.selector);
        cf.createCampaign("x", 0, DURATION);
    }

    function test_CreateRevertsOnBadDuration() public {
        vm.expectRevert(Crowdfunding.InvalidDuration.selector);
        cf.createCampaign("x", GOAL, 1 hours);

        vm.expectRevert(Crowdfunding.InvalidDuration.selector);
        cf.createCampaign("x", GOAL, 91 days);
    }

    /*-------------------------- contribute --------------------------*/

    function test_Contribute() public {
        uint256 id = _create();

        vm.expectEmit(true, true, false, true);
        emit Contributed(id, alice, 3 ether);
        vm.prank(alice);
        cf.contribute{value: 3 ether}(id);

        assertEq(cf.contributions(id, alice), 3 ether);
        assertEq(cf.getCampaign(id).totalRaised, 3 ether);
        assertEq(address(cf).balance, 3 ether);
    }

    function test_ContributeRevertsAfterDeadline() public {
        uint256 id = _create();
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        vm.expectRevert(Crowdfunding.CampaignEnded.selector);
        cf.contribute{value: 1 ether}(id);
    }

    function test_ContributeRevertsOnZero() public {
        uint256 id = _create();
        vm.prank(alice);
        vm.expectRevert(Crowdfunding.ZeroContribution.selector);
        cf.contribute{value: 0}(id);
    }

    function test_ContributeRevertsOnUnknownCampaign() public {
        vm.prank(alice);
        vm.expectRevert(Crowdfunding.CampaignNotFound.selector);
        cf.contribute{value: 1 ether}(42);
    }

    /*-------------------------- withdraw ----------------------------*/

    function test_WithdrawAfterSuccess() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: 6 ether}(id);
        vm.prank(bob);
        cf.contribute{value: 5 ether}(id);

        vm.warp(block.timestamp + DURATION);

        uint256 before = creator.balance;
        vm.prank(creator);
        cf.withdraw(id);

        assertEq(creator.balance - before, 11 ether);
        assertEq(address(cf).balance, 0);
        assertTrue(cf.getCampaign(id).withdrawn);
    }

    function test_WithdrawRevertsBeforeDeadline() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: GOAL}(id);

        vm.prank(creator);
        vm.expectRevert(Crowdfunding.CampaignNotEnded.selector);
        cf.withdraw(id);
    }

    function test_WithdrawRevertsIfGoalNotReached() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: 1 ether}(id);
        vm.warp(block.timestamp + DURATION);

        vm.prank(creator);
        vm.expectRevert(Crowdfunding.GoalNotReached.selector);
        cf.withdraw(id);
    }

    function test_WithdrawRevertsIfNotCreator() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: GOAL}(id);
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        vm.expectRevert(Crowdfunding.NotCreator.selector);
        cf.withdraw(id);
    }

    function test_WithdrawTwiceReverts() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: GOAL}(id);
        vm.warp(block.timestamp + DURATION);

        vm.startPrank(creator);
        cf.withdraw(id);
        vm.expectRevert(Crowdfunding.AlreadyWithdrawn.selector);
        cf.withdraw(id);
        vm.stopPrank();
    }

    /*--------------------------- refund -----------------------------*/

    function test_RefundAfterFailure() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: 2 ether}(id);
        vm.prank(bob);
        cf.contribute{value: 3 ether}(id);

        vm.warp(block.timestamp + DURATION);

        uint256 before = alice.balance;
        vm.prank(alice);
        cf.refund(id);

        assertEq(alice.balance - before, 2 ether);
        assertEq(cf.contributions(id, alice), 0);
        assertEq(address(cf).balance, 3 ether); // bob's funds untouched
    }

    function test_RefundRevertsBeforeDeadline() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: 1 ether}(id);

        vm.prank(alice);
        vm.expectRevert(Crowdfunding.CampaignNotEnded.selector);
        cf.refund(id);
    }

    function test_RefundRevertsIfGoalReached() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: GOAL}(id);
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        vm.expectRevert(Crowdfunding.GoalReached.selector);
        cf.refund(id);
    }

    function test_RefundTwiceReverts() public {
        uint256 id = _create();
        vm.prank(alice);
        cf.contribute{value: 1 ether}(id);
        vm.warp(block.timestamp + DURATION);

        vm.startPrank(alice);
        cf.refund(id);
        vm.expectRevert(Crowdfunding.NothingToRefund.selector);
        cf.refund(id);
        vm.stopPrank();
    }

    function test_RefundReentrancyIsBlocked() public {
        uint256 id = _create();

        // honest contributor funds sit in the contract too
        vm.prank(bob);
        cf.contribute{value: 4 ether}(id);

        RefundAttacker attacker = new RefundAttacker(cf);
        vm.deal(address(attacker), 1 ether);
        attacker.contribute{value: 1 ether}(id);

        vm.warp(block.timestamp + DURATION);
        attacker.attack();

        // attacker only gets its own 1 ether back; bob's 4 ether is safe
        assertEq(address(attacker).balance, 1 ether);
        assertEq(address(cf).balance, 4 ether);
    }

    /*--------------------------- fuzz -------------------------------*/

    function testFuzz_ContributionsAccumulate(uint96 a, uint96 b) public {
        a = uint96(bound(a, 1, 50 ether));
        b = uint96(bound(b, 1, 50 ether));
        uint256 id = _create();

        vm.prank(alice);
        cf.contribute{value: a}(id);
        vm.prank(bob);
        cf.contribute{value: b}(id);

        assertEq(cf.getCampaign(id).totalRaised, uint256(a) + b);
        assertEq(address(cf).balance, uint256(a) + b);
        assertEq(cf.isSuccessful(id), uint256(a) + b >= GOAL);
    }

    function testFuzz_FailedCampaignFullyRefundable(uint96 a, uint96 b) public {
        a = uint96(bound(a, 1, 4 ether));
        b = uint96(bound(b, 1, 4 ether)); // always < GOAL
        uint256 id = _create();

        vm.prank(alice);
        cf.contribute{value: a}(id);
        vm.prank(bob);
        cf.contribute{value: b}(id);
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        cf.refund(id);
        vm.prank(bob);
        cf.refund(id);

        assertEq(address(cf).balance, 0);
    }
}
