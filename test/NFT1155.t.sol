// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {NFT1155} from "../src/tokens/NFT1155.sol";

/**
 * @title  NFT1155Test
 * @notice Foundry tests for NFT1155 — covers every P1-I3 acceptance criterion.
 *
 * Run:
 *   forge test --match-contract NFT1155Test -vv
 *
 * Gas snapshot:
 *   forge snapshot --match-contract NFT1155Test
 */
contract NFT1155Test is Test {
    // ── Contracts & actors ───────────────────────────────────────────────────
    NFT1155 internal nft;

    address internal admin   = makeAddr("admin");
    address internal minter  = makeAddr("minter");
    address internal airdrop = makeAddr("airdrop");
    address internal alice   = makeAddr("alice");
    address internal bob     = makeAddr("bob");
    address internal carol   = makeAddr("carol");
    address internal dave    = makeAddr("dave");
    address internal eve     = makeAddr("eve");
    address internal nobody  = makeAddr("nobody");

    // ── Constants ────────────────────────────────────────────────────────────
    string  constant BASE_URI = "ipfs://QmTest1155/";

    bytes32 internal constant MINTER_ROLE  = keccak256("MINTER_ROLE");
    bytes32 internal constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    // Token IDs used across tests
    uint256 constant ID_COMMON = 1;   // has max supply set
    uint256 constant ID_RARE   = 2;   // has lower max supply
    uint256 constant ID_FREE   = 99;  // no max supply (unlimited)

    // ─────────────────────────────────────────────────────────────────────────
    // Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setUp() public {
        nft = new NFT1155("Test Editions", "TEDT", BASE_URI, admin);

        vm.startPrank(admin);
        nft.grantRole(MINTER_ROLE,  minter);
        nft.grantRole(AIRDROP_ROLE, airdrop);

        // Configure supply caps
        nft.setMaxSupply(ID_COMMON, 100);
        nft.setMaxSupply(ID_RARE,   10);
        // ID_FREE (99) left at 0 = unlimited
        vm.stopPrank();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deployment sanity
    // ─────────────────────────────────────────────────────────────────────────

    function test_DeploymentState() public view {
        assertEq(nft.name(),   "Test Editions");
        assertEq(nft.symbol(), "TEDT");
        assertEq(nft.baseURI(), BASE_URI);
        assertEq(nft.maxSupply(ID_COMMON), 100);
        assertEq(nft.maxSupply(ID_RARE),   10);
        assertEq(nft.maxSupply(ID_FREE),   0);
        assertEq(nft.totalMinted(ID_COMMON), 0);
    }

    function test_AdminHasAllRoles() public view {
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nft.hasRole(MINTER_ROLE,              admin));
        assertTrue(nft.hasRole(AIRDROP_ROLE,             admin));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testMintSingle
    // ─────────────────────────────────────────────────────────────────────────

    function testMintSingle() public {
        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 5, "");

        assertEq(nft.balanceOf(alice, ID_COMMON), 5);
        assertEq(nft.totalMinted(ID_COMMON), 5);
    }

    function testMintSingleEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(nft));
        emit NFT1155.TokenMinted(alice, ID_COMMON, 3);

        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 3, "");
    }

    function testMintUnlimitedID() public {
        // ID_FREE has no cap — mint a large amount
        vm.prank(minter);
        nft.mint(alice, ID_FREE, 50_000, "");
        assertEq(nft.balanceOf(alice, ID_FREE), 50_000);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testMintBatch — multiple IDs to single address
    // ─────────────────────────────────────────────────────────────────────────

    function testMintBatch() public {
        uint256[] memory ids     = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);

        ids[0] = ID_COMMON;  amounts[0] = 10;
        ids[1] = ID_RARE;    amounts[1] = 3;
        ids[2] = ID_FREE;    amounts[2] = 1000;

        vm.prank(minter);
        nft.mintBatch(alice, ids, amounts, "");

        assertEq(nft.balanceOf(alice, ID_COMMON), 10);
        assertEq(nft.balanceOf(alice, ID_RARE),   3);
        assertEq(nft.balanceOf(alice, ID_FREE),   1000);

        assertEq(nft.totalMinted(ID_COMMON), 10);
        assertEq(nft.totalMinted(ID_RARE),   3);
        assertEq(nft.totalMinted(ID_FREE),   1000);
    }

    function testMintBatchEmitsEventPerID() public {
        uint256[] memory ids     = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = ID_COMMON; amounts[0] = 2;
        ids[1] = ID_RARE;   amounts[1] = 1;

        vm.expectEmit(true, true, false, true, address(nft));
        emit NFT1155.TokenMinted(alice, ID_COMMON, 2);

        vm.expectEmit(true, true, false, true, address(nft));
        emit NFT1155.TokenMinted(alice, ID_RARE, 1);

        vm.prank(minter);
        nft.mintBatch(alice, ids, amounts, "");
    }

    function testMintBatchArrayMismatchReverts() public {
        uint256[] memory ids     = new uint256[](2);
        uint256[] memory amounts = new uint256[](1); // wrong length
        ids[0] = ID_COMMON; ids[1] = ID_RARE;
        amounts[0] = 1;

        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155.ArrayLengthMismatch.selector, 2, 1)
        );
        nft.mintBatch(alice, ids, amounts, "");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testAirdropBatch — same ID to many recipients
    // ─────────────────────────────────────────────────────────────────────────

    function testAirdropBatch() public {
        address[] memory recipients = new address[](5);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        recipients[3] = dave;
        recipients[4] = eve;

        vm.prank(airdrop);
        nft.airdropBatch(recipients, ID_COMMON, 2); // 5 * 2 = 10 minted

        assertEq(nft.balanceOf(alice, ID_COMMON), 2);
        assertEq(nft.balanceOf(bob,   ID_COMMON), 2);
        assertEq(nft.balanceOf(carol, ID_COMMON), 2);
        assertEq(nft.balanceOf(dave,  ID_COMMON), 2);
        assertEq(nft.balanceOf(eve,   ID_COMMON), 2);

        assertEq(nft.totalMinted(ID_COMMON), 10);
    }

    function testAirdropBatchEmitsEventPerRecipient() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;

        vm.expectEmit(true, true, false, true, address(nft));
        emit NFT1155.TokenMinted(alice, ID_COMMON, 1);

        vm.expectEmit(true, true, false, true, address(nft));
        emit NFT1155.TokenMinted(bob, ID_COMMON, 1);

        vm.prank(airdrop);
        nft.airdropBatch(recipients, ID_COMMON, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testMaxSupplyPerID — set max=10 for id, mint 11, expect revert
    // ─────────────────────────────────────────────────────────────────────────

    function testMaxSupplyPerID() public {
        // ID_RARE has max = 10
        vm.prank(minter);
        nft.mint(alice, ID_RARE, 10, ""); // exactly at cap — should pass

        assertEq(nft.totalMinted(ID_RARE), 10);
        assertEq(nft.remainingSupply(ID_RARE), 0);

        // One more should revert
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(NFT1155.ExceedsMaxSupply.selector, ID_RARE, 1, 0)
        );
        nft.mint(alice, ID_RARE, 1, "");
    }

    function testMaxSupplyAirdropBatchCapCheck() public {
        // ID_COMMON max = 100, airdrop 6 recipients * 20 = 120 — should revert
        address[] memory recipients = new address[](6);
        for (uint256 i; i < 6; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("r", i)));
        }

        vm.prank(airdrop);
        vm.expectRevert(); // ExceedsMaxSupply
        nft.airdropBatch(recipients, ID_COMMON, 20);
    }

    function testUnlimitedSupplyNeverReverts() public {
        vm.prank(minter);
        nft.mint(alice, ID_FREE, 1_000_000, "");
        assertEq(nft.remainingSupply(ID_FREE), type(uint256).max);
    }

    function testSetMaxSupplyBelowMintedReverts() public {
        vm.prank(minter);
        nft.mint(alice, ID_FREE, 50, "");

        // Trying to set max below already-minted should revert
        vm.prank(admin);
        vm.expectRevert("NFT1155: cap below already-minted amount");
        nft.setMaxSupply(ID_FREE, 30);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testBurnAndBurnBatch
    // ─────────────────────────────────────────────────────────────────────────

    function testBurn() public {
        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 10, "");

        vm.prank(alice); // alice burns her own tokens
        nft.burn(alice, ID_COMMON, 4);

        assertEq(nft.balanceOf(alice, ID_COMMON), 6);
    }

    function testBurnBatch() public {
        uint256[] memory ids     = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = ID_COMMON; amounts[0] = 5;
        ids[1] = ID_RARE;   amounts[1] = 3;

        vm.prank(minter);
        nft.mintBatch(alice, ids, amounts, "");

        uint256[] memory burnAmounts = new uint256[](2);
        burnAmounts[0] = 2;
        burnAmounts[1] = 1;

        vm.prank(alice);
        nft.burnBatch(alice, ids, burnAmounts);

        assertEq(nft.balanceOf(alice, ID_COMMON), 3);
        assertEq(nft.balanceOf(alice, ID_RARE),   2);
    }

    function testBurnByApprovedOperator() public {
        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 10, "");

        // Alice approves bob as operator
        vm.prank(alice);
        nft.setApprovalForAll(bob, true);

        // Bob burns on behalf of Alice
        vm.prank(bob);
        nft.burn(alice, ID_COMMON, 5);

        assertEq(nft.balanceOf(alice, ID_COMMON), 5);
    }

    function testBurnUnauthorizedReverts() public {
        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 10, "");

        // nobody cannot burn alice's tokens
        vm.prank(nobody);
        vm.expectRevert(NFT1155.NotOwnerOrApproved.selector);
        nft.burn(alice, ID_COMMON, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testUnauthorizedAccess
    // ─────────────────────────────────────────────────────────────────────────

    function testUnauthorizedMintReverts() public {
        vm.prank(nobody);
        vm.expectRevert();
        nft.mint(alice, ID_COMMON, 1, "");
    }

    function testUnauthorizedMintBatchReverts() public {
        uint256[] memory ids     = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = ID_COMMON; amounts[0] = 1;

        vm.prank(nobody);
        vm.expectRevert();
        nft.mintBatch(alice, ids, amounts, "");
    }

    function testUnauthorizedAirdropReverts() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        vm.prank(nobody);
        vm.expectRevert();
        nft.airdropBatch(recipients, ID_COMMON, 1);
    }

    function testMinterCannotAirdrop() public {
        // MINTER_ROLE cannot call airdropBatch (needs AIRDROP_ROLE)
        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        vm.prank(minter);
        vm.expectRevert();
        nft.airdropBatch(recipients, ID_COMMON, 1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testSafeTransferFrom, testSafeBatchTransferFrom
    // ─────────────────────────────────────────────────────────────────────────

    function testSafeTransferFrom() public {
        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 10, "");

        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, ID_COMMON, 3, "");

        assertEq(nft.balanceOf(alice, ID_COMMON), 7);
        assertEq(nft.balanceOf(bob,   ID_COMMON), 3);
    }

    function testSafeBatchTransferFrom() public {
        uint256[] memory ids     = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = ID_COMMON; amounts[0] = 10;
        ids[1] = ID_RARE;   amounts[1] = 5;

        vm.prank(minter);
        nft.mintBatch(alice, ids, amounts, "");

        uint256[] memory transferAmounts = new uint256[](2);
        transferAmounts[0] = 4;
        transferAmounts[1] = 2;

        vm.prank(alice);
        nft.safeBatchTransferFrom(alice, bob, ids, transferAmounts, "");

        assertEq(nft.balanceOf(alice, ID_COMMON), 6);
        assertEq(nft.balanceOf(alice, ID_RARE),   3);
        assertEq(nft.balanceOf(bob,   ID_COMMON), 4);
        assertEq(nft.balanceOf(bob,   ID_RARE),   2);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // testPauseBlocks — all mint/transfer blocked when paused
    // ─────────────────────────────────────────────────────────────────────────

    function testPauseBlocksMint() public {
        vm.prank(admin);
        nft.pause();

        vm.prank(minter);
        vm.expectRevert();
        nft.mint(alice, ID_COMMON, 1, "");
    }

    function testPauseBlocksMintBatch() public {
        vm.prank(admin);
        nft.pause();

        uint256[] memory ids     = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = ID_COMMON; amounts[0] = 1;

        vm.prank(minter);
        vm.expectRevert();
        nft.mintBatch(alice, ids, amounts, "");
    }

    function testPauseBlocksAirdrop() public {
        vm.prank(admin);
        nft.pause();

        address[] memory recipients = new address[](1);
        recipients[0] = alice;

        vm.prank(airdrop);
        vm.expectRevert();
        nft.airdropBatch(recipients, ID_COMMON, 1);
    }

    function testPauseBlocksTransfer() public {
        // Mint first (not paused)
        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 5, "");

        // Now pause
        vm.prank(admin);
        nft.pause();

        // Transfer should revert
        vm.prank(alice);
        vm.expectRevert();
        nft.safeTransferFrom(alice, bob, ID_COMMON, 1, "");
    }

    function testUnpauseRestoresMinting() public {
        vm.prank(admin);
        nft.pause();

        vm.prank(admin);
        nft.unpause();

        vm.prank(minter);
        nft.mint(alice, ID_COMMON, 1, "");
        assertEq(nft.balanceOf(alice, ID_COMMON), 1);
    }

    function testNonAdminCannotPause() public {
        vm.prank(minter);
        vm.expectRevert();
        nft.pause();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // URI tests
    // ─────────────────────────────────────────────────────────────────────────

    function testURIFallback() public view {
        // No per-id URI set → base URI fallback
        assertEq(nft.uri(ID_COMMON), "ipfs://QmTest1155/1.json");
        assertEq(nft.uri(ID_RARE),   "ipfs://QmTest1155/2.json");
        assertEq(nft.uri(42),        "ipfs://QmTest1155/42.json");
    }

    function testPerIDURIOverride() public {
        vm.prank(admin);
        nft.setURI(ID_COMMON, "ipfs://QmCustom/badge-metadata.json");

        // ID_COMMON now returns custom URI
        assertEq(nft.uri(ID_COMMON), "ipfs://QmCustom/badge-metadata.json");

        // ID_RARE still uses fallback
        assertEq(nft.uri(ID_RARE), "ipfs://QmTest1155/2.json");
    }

    function testSetBaseURIUpdatesAllFallbacks() public {
        vm.prank(admin);
        nft.setBaseURI("ipfs://QmNewHash/");

        assertEq(nft.uri(ID_RARE), "ipfs://QmNewHash/2.json");
    }

    function testNonAdminCannotSetURI() public {
        vm.prank(nobody);
        vm.expectRevert();
        nft.setURI(ID_COMMON, "ipfs://malicious/");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ERC-165
    // ─────────────────────────────────────────────────────────────────────────

    function testSupportsERC1155Interface() public view {
        // ERC-1155 interface ID
        assertTrue(nft.supportsInterface(0xd9b67a26));
    }

    function testSupportsAccessControl() public view {
        // Import IAccessControl from OZ to get the correct interfaceId
        // bytes4(keccak256("hasRole(bytes32,address)")) ^
        // bytes4(keccak256("getRoleAdmin(bytes32)")) ^
        // bytes4(keccak256("grantRole(bytes32,address)")) ^
        // bytes4(keccak256("revokeRole(bytes32,address)")) ^
        // bytes4(keccak256("renounceRole(bytes32,address)"))
        assertTrue(nft.supportsInterface(0x7965db0b));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Gas benchmarks (captured by forge snapshot)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Gas: single mint of 1 token
    function test_gas_MintSingle() public {
        vm.prank(minter);
        nft.mint(alice, ID_FREE, 1, "");
    }

    /// @dev Gas: mintBatch — 10 different IDs in one tx
    function test_gas_MintBatch10IDs() public {
        uint256[] memory ids     = new uint256[](10);
        uint256[] memory amounts = new uint256[](10);
        for (uint256 i; i < 10; i++) {
            ids[i]     = 100 + i; // use IDs with no cap
            amounts[i] = 5;
        }
        vm.prank(minter);
        nft.mintBatch(alice, ids, amounts, "");
    }

    /// @dev Gas: 10 individual mints (compare vs mintBatch above)
    function test_gas_Mint10Individual() public {
        vm.startPrank(minter);
        for (uint256 i; i < 10; i++) {
            nft.mint(alice, 100 + i, 5, "");
        }
        vm.stopPrank();
    }

    /// @dev Gas: airdropBatch to 10 recipients
    function test_gas_AirdropBatch10() public {
        address[] memory recipients = new address[](10);
        for (uint256 i; i < 10; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("r", i)));
        }
        vm.prank(airdrop);
        nft.airdropBatch(recipients, ID_FREE, 1);
    }
}
