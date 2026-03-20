// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {
    IAccessControl
} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {NFT721} from "../src/tokens/NFT721.sol";

/**
 * @title  NFT721Test
 * @notice Foundry tests for NFT721 — covers every P1-I2 acceptance criterion.
 *
 * Run:
 *   forge test --match-contract NFT721Test -vv
 *
 * Gas snapshot:
 *   forge snapshot --match-contract NFT721Test
 */
contract NFT721Test is Test {
    // ── Contracts & actors ───────────────────────────────────────────────────
    NFT721 internal nft;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal airdrop = makeAddr("airdrop");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal eve = makeAddr("eve");
    address internal nobody = makeAddr("nobody");

    // ── Constants ────────────────────────────────────────────────────────────
    string constant BASE_URI = "ipfs://Qmtest/";
    uint256 constant MAX_SUPPLY = 100;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // Setup
    // ──────────────────────────────────────────────────────────────────────────

    function setUp() public {
        // Deploy with max supply = 100, admin = admin address
        nft = new NFT721("Test NFT", "TNFT", BASE_URI, MAX_SUPPLY, admin);

        // Grant dedicated roles to separate actors
        vm.startPrank(admin);
        nft.grantRole(MINTER_ROLE, minter);
        nft.grantRole(AIRDROP_ROLE, airdrop);
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Deployment sanity checks
    // ──────────────────────────────────────────────────────────────────────────

    function test_DeploymentState() public view {
        assertEq(nft.name(), "Test NFT");
        assertEq(nft.symbol(), "TNFT");
        assertEq(nft.maxSupply(), MAX_SUPPLY);
        assertEq(nft.baseURI(), BASE_URI);
        assertEq(nft.totalSupply(), 0);
    }

    function test_AdminHasAllRoles() public view {
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nft.hasRole(MINTER_ROLE, admin));
        assertTrue(nft.hasRole(AIRDROP_ROLE, admin));
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testMintSingle — mint 1 to Alice, check ownerOf
    // ──────────────────────────────────────────────────────────────────────────

    function testMintSingle() public {
        vm.prank(minter);
        nft.mint(alice, 1);

        // ERC721A token IDs start at 1
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.totalSupply(), 1);
    }

    function testMintEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(nft));
        emit NFT721.NFTMinted(alice, 1, 3);

        vm.prank(minter);
        nft.mint(alice, 3);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testBatchMint — mint to 5 addresses, verify balances
    // ──────────────────────────────────────────────────────────────────────────

    function testBatchMint() public {
        address[] memory recipients = new address[](5);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        recipients[3] = dave;
        recipients[4] = eve;

        uint256[] memory quantities = new uint256[](5);
        quantities[0] = 1;
        quantities[1] = 2;
        quantities[2] = 3;
        quantities[3] = 1;
        quantities[4] = 2;

        vm.prank(airdrop);
        nft.batchMint(recipients, quantities);

        assertEq(nft.balanceOf(alice), 1);
        assertEq(nft.balanceOf(bob), 2);
        assertEq(nft.balanceOf(carol), 3);
        assertEq(nft.balanceOf(dave), 1);
        assertEq(nft.balanceOf(eve), 2);

        assertEq(nft.totalSupply(), 9);
    }

    function testBatchMintEmitsEventsPerRecipient() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory quantities = new uint256[](2);
        quantities[0] = 2;
        quantities[1] = 3;

        // Alice gets tokens 1-2, Bob gets tokens 3-5
        vm.expectEmit(true, false, false, true, address(nft));
        emit NFT721.NFTMinted(alice, 1, 2);

        vm.expectEmit(true, false, false, true, address(nft));
        emit NFT721.NFTMinted(bob, 3, 3);

        vm.prank(airdrop);
        nft.batchMint(recipients, quantities);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testUnauthorizedMint — expect revert when non-minter calls mint
    // ──────────────────────────────────────────────────────────────────────────

    function testUnauthorizedMint() public {
        vm.prank(nobody);
        vm.expectRevert(); // AccessControl will revert
        nft.mint(alice, 1);
    }

    function testUnauthorizedBatchMint() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 1;

        vm.prank(nobody);
        vm.expectRevert();
        nft.batchMint(recipients, quantities);
    }

    function testMinterCannotCallBatchMint() public {
        // MINTER_ROLE cannot call batchMint (requires AIRDROP_ROLE)
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 1;

        vm.prank(minter);
        vm.expectRevert();
        nft.batchMint(recipients, quantities);
    }

    function testAirdropRoleCannotCallMint() public {
        // AIRDROP_ROLE cannot call mint (requires MINTER_ROLE)
        vm.prank(airdrop);
        vm.expectRevert();
        nft.mint(alice, 1);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testTokenURI — verify correct IPFS URI format
    // ──────────────────────────────────────────────────────────────────────────

    function testTokenURI() public {
        vm.prank(minter);
        nft.mint(alice, 3);

        assertEq(nft.tokenURI(1), "ipfs://Qmtest/1.json");
        assertEq(nft.tokenURI(2), "ipfs://Qmtest/2.json");
        assertEq(nft.tokenURI(3), "ipfs://Qmtest/3.json");
    }

    function testTokenURIAfterBaseURIUpdate() public {
        vm.prank(minter);
        nft.mint(alice, 1);

        vm.prank(admin);
        nft.setBaseURI("ipfs://QmNewHash/");

        assertEq(nft.tokenURI(1), "ipfs://QmNewHash/1.json");
    }

    function testTokenURINonExistentReverts() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testMaxSupply — mint up to cap, then revert on overflow
    // ──────────────────────────────────────────────────────────────────────────

    function testMaxSupply() public {
        // Mint exactly up to the cap
        vm.prank(minter);
        nft.mint(alice, MAX_SUPPLY);

        assertEq(nft.totalSupply(), MAX_SUPPLY);
        assertEq(nft.remainingSupply(), 0);
    }

    function testMaxSupplyOverflowReverts() public {
        vm.prank(minter);
        nft.mint(alice, MAX_SUPPLY);

        // One more should revert
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(NFT721.ExceedsMaxSupply.selector, 1, 0)
        );
        nft.mint(bob, 1);
    }

    function testMaxSupplyPartialFillThenOverflow() public {
        vm.prank(minter);
        nft.mint(alice, 99); // 99 out of 100

        // Minting 2 more exceeds cap by 1
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(NFT721.ExceedsMaxSupply.selector, 2, 1)
        );
        nft.mint(bob, 2);
    }

    function testUnlimitedSupply() public {
        // Deploy a contract with maxSupply = 0 (unlimited)
        NFT721 unlimitedNft = new NFT721(
            "Unlimited",
            "UNL",
            BASE_URI,
            0,
            admin
        );

        vm.prank(admin);
        unlimitedNft.mint(alice, 5000);

        assertEq(unlimitedNft.totalSupply(), 5000);
        assertEq(unlimitedNft.remainingSupply(), type(uint256).max);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testPauseUnpause — revert all mints when paused
    // ──────────────────────────────────────────────────────────────────────────

    function testPauseUnpause() public {
        // Pause
        vm.prank(admin);
        nft.pause();
        assertTrue(nft.paused());

        // mint() should revert
        vm.prank(minter);
        vm.expectRevert();
        nft.mint(alice, 1);

        // batchMint() should revert
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 1;

        vm.prank(airdrop);
        vm.expectRevert();
        nft.batchMint(recipients, quantities);

        // Unpause — mints work again
        vm.prank(admin);
        nft.unpause();
        assertFalse(nft.paused());

        vm.prank(minter);
        nft.mint(alice, 1);
        assertEq(nft.totalSupply(), 1);
    }

    function testNonAdminCannotPause() public {
        vm.prank(minter);
        vm.expectRevert();
        nft.pause();
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testRoleTransfer — admin grants MINTER_ROLE, new minter mints
    // ──────────────────────────────────────────────────────────────────────────

    function testRoleTransfer() public {
        address newMinter = makeAddr("newMinter");

        // newMinter cannot mint yet
        vm.prank(newMinter);
        vm.expectRevert();
        nft.mint(alice, 1);

        // Admin grants the role
        vm.prank(admin);
        nft.grantRole(MINTER_ROLE, newMinter);

        // Now newMinter can mint
        vm.prank(newMinter);
        nft.mint(alice, 5);
        assertEq(nft.balanceOf(alice), 5);
    }

    function testRoleRevoke() public {
        // Admin revokes minter's role
        vm.prank(admin);
        nft.revokeRole(MINTER_ROLE, minter);

        vm.prank(minter);
        vm.expectRevert();
        nft.mint(alice, 1);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // testSetBaseURI — only admin
    // ──────────────────────────────────────────────────────────────────────────

    function testSetBaseURIAdminOnly() public {
        vm.prank(nobody);
        vm.expectRevert();
        nft.setBaseURI("ipfs://malicious/");
    }

    function testSetBaseURIEmitsEvent() public {
        vm.expectEmit(false, false, false, true, address(nft));
        emit NFT721.BaseURIUpdated("ipfs://NewHash/");

        vm.prank(admin);
        nft.setBaseURI("ipfs://NewHash/");
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Edge cases
    // ──────────────────────────────────────────────────────────────────────────

    function testZeroQuantityReverts() public {
        vm.prank(minter);
        vm.expectRevert(NFT721.ZeroQuantity.selector);
        nft.mint(alice, 0);
    }

    function testBatchMintArrayMismatchReverts() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        uint256[] memory quantities = new uint256[](1); // wrong length
        quantities[0] = 1;

        vm.prank(airdrop);
        vm.expectRevert(
            abi.encodeWithSelector(NFT721.ArrayLengthMismatch.selector, 2, 1)
        );
        nft.batchMint(recipients, quantities);
    }

    function testSupportsInterface() public view {
        // ERC-721
        // assertTrue(nft.supportsInterface(0x80ac58cd));
        // AccessControl
        assertTrue(nft.supportsInterface(type(IAccessControl).interfaceId));
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Gas benchmarks (captured by forge snapshot)
    // ──────────────────────────────────────────────────────────────────────────

    /// @dev Labelled with "gas:" prefix so forge snapshot can identify them.
    function test_gas_MintSingle() public {
        vm.prank(minter);
        nft.mint(alice, 1);
    }

    function test_gas_MintTen() public {
        vm.prank(minter);
        nft.mint(alice, 10);
    }

    function test_gas_BatchMintFive() public {
        address[] memory recipients = new address[](5);
        uint256[] memory quantities = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("r", i)));
            quantities[i] = 2;
        }
        vm.prank(airdrop);
        nft.batchMint(recipients, quantities);
    }
}

/// @dev Minimal interface used only for supportsInterface test.
interface IAccessControlInterface {
    function hasRole(bytes32, address) external view returns (bool);
    function getRoleAdmin(bytes32) external view returns (bytes32);
    function grantRole(bytes32, address) external;
    function revokeRole(bytes32, address) external;
    function renounceRole(bytes32, address) external;
}
