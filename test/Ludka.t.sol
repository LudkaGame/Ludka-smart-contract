// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2, StdStyle, Vm} from "../lib/forge-std/src/Test.sol";
import {Ludka} from "../src/Ludka.sol";
import {ILudka} from "../src/interfaces/ILudka.sol";
import {Constants} from "./Constants.sol";

contract TestLudka is Test, Constants {
    Ludka public ludka;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    event Paused(address account);
    event Unpaused(address account);
    modifier asPrankedUser(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }
    function setUp() public {
        vm.createSelectFork("https://sepolia.blast.io", USE_BLOCK);
        ludka = new Ludka(
            alice,
            alice,
            maximumNumberOfDepositsPerRound,
            maximumNumberOfParticipantsPerRound,
            roundDuration,
            valuePerEntry,
            alice,
            protocolFeeBp,
            entropy,
            entropyProvider,
            pythContract,
            weth
        );
    }
    function testDeposit() public {
        /* RoundStatus status = ludka.rounds.status; */
        vm.prank(bob);
        (
            ILudka.RoundStatus status,
            ,
            ,
            ,
            uint40 numberOfParticipants,
            ,
            ,
            ,
            ,

        ) = ludka.rounds(1);
        ludka.deposit{value: valuePerEntry}(
            1,
            userCommitment1,
            0xfd8d2cf88c63688b2713b909dd6e5931e763acae6432fccdb7499c8a975c31b0,
            0
        );
        (status, , , , numberOfParticipants, , , , , ) = ludka.rounds(1);
        assertEq(uint8(status), 1);
        assertEq(numberOfParticipants, 1);
    }
    function testtogglePaused() public asPrankedUser(alice) {
        ludka.togglePaused();
        assertTrue(ludka.paused());
    }
    function test_pause_RevertIf_NotOwner() public asPrankedUser(bob) {
        vm.expectRevert();
        ludka.togglePaused();
    }
    function test_unpause() public asPrankedUser(alice) {
        ludka.togglePaused();
        assertTrue(ludka.paused());
        ludka.togglePaused();
        assertFalse(ludka.paused());
    }
    function expectEmitCheckAll() internal {
        vm.expectEmit({
            checkTopic1: true,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true
        });
    }
    function expectEmitOnlyOne() internal {
        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: false,
            checkTopic3: false,
            checkData: false
        });
    }
}
