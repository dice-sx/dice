pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./Jackpot.sol";


contract SX is Ownable {
    using SafeMath for uint256;

    string constant public name = "DICE.SX";
    string constant public symbol = "DSX";

    uint256 public adminFeePercent = 1;   // 1%
    uint256 public jackpotFeePercent = 1; // 1%
    uint256 public maxRewardPercent = 10; // 10%
    uint256 public minReward = 0.01 ether;
    uint256 public maxReward = 3 ether;
    
    struct Game {
        address player;
        uint256 blockNumber;
        uint256 value;
        uint256 combinations;
        uint256 answer;
        uint256 salt;
    }

    Game[] public games;
    uint256 public gamesFinished;
    uint256 public totalWeisInGame;
    
    Jackpot public nextJackpot;
    Jackpot[] public prevJackpots;

    event GameStarted(
        address indexed player,
        uint256 indexed blockNumber,
        uint256 indexed index,
        uint256 combinations,
        uint256 answer,
        uint256 value
    );
    event GameFinished(
        address indexed player,
        uint256 indexed blockNumber,
        uint256 value,
        uint256 combinations,
        uint256 answer,
        uint256 result
    );

    event JackpotRangeAdded(
        uint256 indexed jackpotIndex,
        address indexed player,
        uint256 indexed begin,
        uint256 end
    );
    event JackpotWinnerSelected(
        uint256 indexed jackpotIndex,
        uint256 offset
    );
    event JackpotRewardPayed(
        uint256 indexed jackpotIndex,
        address indexed player,
        uint256 begin,
        uint256 end,
        uint256 winnerOffset,
        uint256 value
    );

    constructor() public {
        nextJackpot = new Jackpot();
    }

    function () public payable {
        // Coin flip
        uint256 prevBlockHash = uint256(blockhash(block.number - 1));
        play(2, 1 << (prevBlockHash % 2));
    }

    function gamesLength() public view returns(uint256) {
        return games.length;
    }

    function prevJackpotsLength() public view returns(uint256) {
        return prevJackpots.length;
    }

    function updateState() public {
        finishAllGames();

        if (nextJackpot.shouldSelectWinner()) {
            nextJackpot.selectWinner();
            emit JackpotWinnerSelected(prevJackpots.length, nextJackpot.winnerOffset());

            prevJackpots.push(nextJackpot);
            nextJackpot = new Jackpot();
        }
    }

    function playAndFinishJackpot(
        uint256 combinations,
        uint256 answer,
        uint256 jackpotIndex,
        uint256 begin
    ) 
        public
        payable
    {
        finishJackpot(jackpotIndex, begin);
        play(combinations, answer);
    }

    function play(uint256 combinations, uint256 answer) public payable {
        uint256 answerSize = _countBits(answer);
        uint256 possibleReward = msg.value.mul(combinations).div(answerSize);
        require(minReward <= possibleReward && possibleReward <= maxReward, "Possible reward value out of range");
        require(possibleReward <= address(this).balance.mul(maxRewardPercent).div(100), "Possible reward value out of range");
        require(answer > 0 && answer < (1 << combinations) - 1, "Answer should not contain all bits set");
        require(2 <= combinations && combinations <= 100, "Combinations value is invalid");

        // Update
        updateState();

        // Play game
        uint256 blockNumber = block.number + 1;
        emit GameStarted(
            msg.sender,
            blockNumber,
            games.length,
            combinations,
            answer,
            msg.value
        );
        games.push(Game({
            player: msg.sender,
            blockNumber: blockNumber,
            value: msg.value,
            combinations: combinations,
            answer: answer,
            salt: nextJackpot.totalLength()
        }));

        (uint256 begin, uint256 end) = nextJackpot.addRange(msg.sender, msg.value);
        emit JackpotRangeAdded(
            prevJackpots.length,
            msg.sender,
            begin,
            end
        );

        totalWeisInGame = totalWeisInGame.add(possibleReward);
        require(totalWeisInGame <= address(this).balance, "Not enough balance");
    }

    function finishAllGames() public returns(uint256 count) {
        while (finishNextGame()) {
            count += 1;
        }
    }

    function finishNextGame() public returns(bool) {
        if (gamesFinished >= games.length) {
            return false;
        }

        Game storage game = games[gamesFinished];
        if (game.blockNumber >= block.number) {
            return false;
        }

        uint256 hash = uint256(blockhash(game.blockNumber));
        bool lose = (hash == 0);
        hash = uint256(keccak256(abi.encodePacked(hash, game.salt)));

        uint256 answerSize = _countBits(game.answer);
        uint256 reward = game.value.mul(game.combinations).div(answerSize);
        
        uint256 result = 1 << (hash % game.combinations);
        if (!lose && (result & game.answer) != 0) {
            uint256 adminFee = reward.mul(adminFeePercent).div(100);
            uint256 jackpotFee = reward.mul(jackpotFeePercent).div(100);

            owner().send(adminFee);                                 // solium-disable-line security/no-send
            address(nextJackpot).send(jackpotFee);                  // solium-disable-line security/no-send
            game.player.send(reward.sub(adminFee).sub(jackpotFee)); // solium-disable-line security/no-send
        }

        emit GameFinished(
            game.player,
            game.blockNumber,
            game.value,
            game.combinations,
            game.answer,
            result
        );
        delete games[gamesFinished];
        totalWeisInGame = totalWeisInGame.sub(reward);
        gamesFinished += 1;
        return true;
    }

    function finishJackpot(uint256 jackpotIndex, uint256 begin) public {
        if (jackpotIndex >= prevJackpots.length) {
            return;
        }

        Jackpot jackpot = prevJackpots[jackpotIndex];
        if (address(jackpot).balance == 0) {
            return;
        }

        (uint256 end, address player) = jackpot.ranges(begin);
        uint256 winnerOffset = jackpot.winnerOffset();
        uint256 value = address(jackpot).balance;
        jackpot.payJackpot(begin);
        delete prevJackpots[jackpotIndex];
        emit JackpotRewardPayed(
            jackpotIndex,
            player,
            begin,
            end,
            winnerOffset,
            value
        );
    }

    // Admin methods

    function setAdminFeePercent(uint256 feePercent) public onlyOwner {
        require(feePercent <= 2, "Should be <= 2%");
        adminFeePercent = feePercent;
    }

    function setJackpotFeePercent(uint256 feePercent) public onlyOwner {
        require(feePercent <= 3, "Should be <= 3%");
        jackpotFeePercent = feePercent;
    }

    function setMaxRewardPercent(uint256 value) public onlyOwner {
        require(value <= 100, "Should not exceed 100%");
        maxRewardPercent = value;
    }

    function setMinReward(uint256 value) public onlyOwner {
        minReward = value;
    }

    function setMaxReward(uint256 value) public onlyOwner {
        maxReward = value;
    }

    function putToBank() public payable onlyOwner {
    }

    function getFromBank(uint256 value) public onlyOwner {
        msg.sender.transfer(value);
        require(totalWeisInGame <= address(this).balance, "Not enough balance");
    }

    function _countBits(uint256 arg) internal pure returns(uint256 count) {
        uint256 value = arg;
        while (value != 0) {
            value &= value - 1; // clear the least significant bit set
            count++;
        }
    }
}
