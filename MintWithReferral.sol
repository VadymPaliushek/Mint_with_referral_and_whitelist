// SPDX-License-Identifier: MIT

pragma solidity >= 0.7 .0 < 0.9 .0;

/// @title BallisticFreaks contract
/// @author Gustas K (ballisticfreaks@gmail.com)

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BallisticFreaksNFT is ERC721Enumerable,
Ownable {
    using Strings
    for uint256;

    /// @notice contract is created with 2 founders. So withdrawal is split 50/50
    address public coFounder;

    string public baseURI;
    string public notRevealedUri;
    string public baseExtension = ".json";

    /// @notice edit these before launching contract
    /// @dev only ReferralRewardPercentage & costToCreateReferral is editable
    uint8 public referralRewardPercentage = 10;
    uint16 public nonce = 1;
    uint16 constant public maxSupply = 10000;
    uint256 public cost = 0.02 ether;
    uint256 public whitelistedCost = 0.01 ether;
    uint256 public referralCost = 0.01 ether;
    uint256 public costToCreateReferral = 25 ether;

    bool public paused = false;
    bool public revealed = false;
    bool public frozenURI = false;

    /// @notice used to find unminted ID
    uint16[maxSupply] public mints;

    mapping(address => uint) public addressesReferred;
    mapping(address => bool) public whitelisted;
    mapping(string => bool) public referralCodeIsTaken;
    mapping(string => address) internal ownerOfCode;

    constructor(string memory _name,
        string memory _symbol,
        address _coFounder,
        string memory _unrevealedURI) ERC721(_name, _symbol) {
        setUnrevealedURI(_unrevealedURI);
        coFounder = _coFounder;
        
        /// @notice adds all possible IDs to mints[]. So you don't have to manually type thousands of numbers into an array
        for (uint16 i = 0; i < maxSupply; ++i) {
            mints[i] = i;
        }
    }

    modifier notPaused {
        require(!paused);
        _;
    }

    function _baseURI() internal view virtual override returns(string memory) {
        return baseURI;
    }

    /// @notice removes Whitelist after the users mints
    function _removeWhitelist(address _address) internal {
        require(whitelisted[_address] == true, "Address is not whitelisted");
        whitelisted[_address] = false;
    }

    /// @notice returns random number
    /// @dev this function is not very secure. While it provides randomness, it can be abused. But in our case for snipers it's not worth the hussle.
    /// wouldn't use it for anything more that could have a big financial gain.
   function random(uint _limit) internal returns(uint16) {
        uint randomnumber = (uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))) % (_limit + 1));
        nonce++;
        return uint16(randomnumber);
    }

    /// @notice calls for random number and picks corresponding NFT
    /// @dev deletes used ID from array and moves the last uint to it's place
    function findUnminted() internal returns(uint) {
        uint supply = totalSupply();
        uint index = random(maxSupply - supply - 1);
        uint chosenNft = mints[index];
        uint swapNft = mints[maxSupply - supply - 1];
        mints[index] = uint16(swapNft);
        return (chosenNft);
    }

    /// @notice Chosen code (string) get's assigned to address. Whenever the code is used in mint, assigned address is paid
    function createRefferalCode(address _address, string memory _code) public payable notPaused {
        require(keccak256(abi.encodePacked(_code)) != keccak256(abi.encodePacked("")), "Referral Code can't be empty");
        require(referralCodeIsTaken[_code] != true, "Referral Code is already taken");

        if (msg.sender != owner()) {
            require(msg.value >= costToCreateReferral, "Value should be equal or greater than ReferralCost");
        }

        referralCodeIsTaken[_code] = true;
        ownerOfCode[_code] = _address;
    }

    /// @notice Seperate mint for Whitelisted addresses to not overdue on code complexity. Whitelisted mint allows for only 1 mint
    /// @dev Whitelist allows only 1 mint. After mint removeWhitelist function is called.
    function whitelistedMint() public payable notPaused {
        require(whitelisted[msg.sender], "You are not whitelisted");
        uint256 supply = totalSupply();
        require(supply + 1 <= maxSupply);
        require(msg.value >= whitelistedCost);
        _removeWhitelist(msg.sender);
        _safeMint(msg.sender, findUnminted());
    }

    /// @notice mint function with referral code to give user discount and pay referral
    /// @dev function has an extra input - string. It is used for referral code. If the user does not put any code string looks like this "".
    function mint(address _to, uint256 _mintAmount, string memory _code) public payable notPaused {
        uint256 supply = totalSupply();
        require(_mintAmount > 0);
        require(supply + _mintAmount <= maxSupply);
        require(referralCodeIsTaken[_code] == true || keccak256(abi.encodePacked(_code)) == keccak256(abi.encodePacked("")), "Referral not valid, find a valid code or leave the string empty ");

        if (msg.sender != owner()) {
            if (referralCodeIsTaken[_code] == true) {
                require(ownerOfCode[_code] != msg.sender, "You can't referr yoursef");
                require(msg.value >= (referralCost * _mintAmount), "ReferralMint: Not enough ether");
            } else {
                require(msg.value >= cost * _mintAmount, "MintWithoutReferral: Not enough ether");
            }
        }

        for (uint256 i = 0; i < _mintAmount; i++) {
            _safeMint(_to, findUnminted());
        }

        if (referralCodeIsTaken[_code] == true) {
            payable(ownerOfCode[_code]).transfer(msg.value / 100 * referralRewardPercentage);
        }
    }


    function walletOfOwner(address _owner) public view returns(uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);

        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns(string memory) {
        require(_exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if(revealed == false) {
            return notRevealedUri;
        }

        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension)) : "";
    }

    //only owner
    function changeReferralReward(uint8 _percentage) public onlyOwner {
        require(_percentage <= 100);
        referralRewardPercentage = _percentage;
    }

    function changeReferralCost(uint _cost) public onlyOwner {
        costToCreateReferral = _cost;
    }

    function setWhitelist(address _address) public onlyOwner {
        require(whitelisted[_address] == false, "Address is whitelisted");
        whitelisted[_address] = true;
    }

    function freezeURI() public onlyOwner {
        frozenURI = true;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        require(!frozenURI, "URI is frozen");
        baseURI = _newBaseURI;
    }

    function setUnrevealedURI(string memory _unrevealedURI) public onlyOwner {
        require(!frozenURI, "URI is frozen");
        notRevealedUri = _unrevealedURI;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function reveal() public onlyOwner {
        revealed = true;
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    /// @notice only co-founder can call this
    function editCoFounder(address _address) public {
        require(msg.sender == coFounder);
        coFounder = _address;
    }


    /// @notice balance is split 50/50 to founder & coFounder
    function withdraw() public payable onlyOwner {
        uint halfBalance = address(this).balance / 2;
        (bool oc, ) = payable(owner()).call {value: halfBalance}("");
        (bool cc, ) = payable(coFounder).call {value: halfBalance}("");
        require(oc && cc);
    }
}
