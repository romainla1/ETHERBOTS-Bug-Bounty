pragma solidity ^0.4.17;

import "./EtherbotsBattle.sol";
import "./Battle.sol";
import "./Base.sol";
import "./AccessControl.sol";


contract TwoPlayerCommitRevealBattle is Battle, Pausable {


    EtherbotsBattle base;

    function TwoPlayerCommitRevealBattle(EtherbotsBattle _base) public {
        base = _base;
    }

    function setBase(EtherbotsBattle _base) external onlyOwner {
        base = _base;
    }

    // Battle interface implementation.
    function name() external view returns (string) {
        return "2PCR";
    }

    function playerCount() external view returns (uint) {
        return duelingPlayers;
    }

    function battleCount() external view returns (uint) {
        return duels.length;
    }

    function winnersOf(uint _duelId) external view returns (address[16] winnerAddresses) {
        uint8 max = 16;
        if (duelIdToAttackers[_duelId].length < max) {
            max = uint8(duelIdToAttackers[_duelId].length);
        }
        for (uint8 i = 0; i < max; i++) {
            if (duelIdToAttackers[_duelId][i].isWinner) {
                winnerAddresses[i] = duelIdToAttackers[_duelId][i].owner;
            } else {
                winnerAddresses[i] = duels[_duelId].defenderAddress;
            }
        }
    }

    function winnerOf(uint battleId, uint index) external view returns (address) {
        Attacker memory a = duelIdToAttackers[battleId][index];
        Duel memory d = duels[battleId];
        return a.isWinner ? a.owner : d.defenderAddress;
    }

    function loserOf(uint battleId, uint index) external view returns (address) {
        Attacker memory a = duelIdToAttackers[battleId][index];
        Duel memory d = duels[battleId];
        return a.isWinner ? d.defenderAddress : a.owner;
    }

    enum DuelStatus {
        Open,
        Exhausted,
        Completed,
        Cancelled
    }

    // mapping (uint => address) public battleIdToWinnerAddress;
    // TODO: packing?
    struct Duel {
        uint feeRemaining;
        uint[] defenderParts;
        bytes32 defenderCommit;
        uint64 revealTime;
        address defenderAddress;
        DuelStatus status;
    }

    struct Attacker {
        address owner;
        uint[] parts;
        uint8[] moves;
        bool isWinner;
    }

    mapping (uint => Attacker[]) public duelIdToAttackers;
    // ID maps to index in battles array.
    // TODO: do we need this?
    // TODO: don't think we ever update it
    // if we want to find all the duels for a user, just use external view
    // mapping (address => uint[]) public addressToDuels;

    Duel[] public duels;
    uint public duelingPlayers;

    function getAttackersMoveFromDuelIdAndIndex(uint index, uint i, uint8 move) external view returns (uint8) {
        return duelIdToAttackers[index][i].moves[move];
    }

    function getAttackersPartsFromDuelIdAndIndex(uint index, uint i) external view returns (uint, uint, uint, uint) {
        Attacker memory a = duelIdToAttackers[index][i];
        return (a.parts[0], a.parts[1], a.parts[2], a.parts[3]);
    }

    function getAttackersLengthFromDuelId(uint index) external view returns (uint) {
        return duelIdToAttackers[index].length;
    }

    function getDefendersPartsFromDuelId(uint index) external view returns (uint, uint, uint, uint) {
        return (duels[index].defenderParts[0], duels[index].defenderParts[1],
            duels[index].defenderParts[2], duels[index].defenderParts[3]);
    }

    function getDuelFromId(uint index) external view returns (
        uint, uint, uint, uint, uint, bytes32, uint64, address, DuelStatus
    ) {
        Duel memory _duel = duels[index];
        return (_duel.feeRemaining, _duel.defenderParts[0], _duel.defenderParts[1],
            _duel.defenderParts[2], _duel.defenderParts[3], _duel.defenderCommit,
            _duel.revealTime, _duel.defenderAddress, _duel.status);
    }

    function getAllDuelsAndStatuses() external view returns (bytes32[]) {
        
        uint totalDuels = duels.length;
        uint resultIndex = 0;

        bytes32[] memory idAndStatus = new bytes32[](totalDuels);

        for (uint duelId = 0; duelId < totalDuels; duelId++) {

            Duel memory d = duels[duelId];

            bytes32 b;

            b = bytes32(duelId);
            
            b = b << 8;
            b = bytes32(uint8(d.status));

     
            idAndStatus[resultIndex] = b;
            resultIndex++;

        }

        return idAndStatus;
    }

    /*
    =========================
     OWNER CONTROLLED FIELDS
    =========================
    */
    // centrally controlled fields
    // CONSIDER: can users ever change these (e.g. different time per battle)
    // CONSIDER: how do we incentivize users to fight 'harder' bots
    uint8 public maxAttackers = 1;
    uint public maxRevealTime = 2 hours;
    uint public attackerFee = 0.0001 ether; // necessary because fighting rewards parts which have eth value
    uint public defenderFee = 0.0001 ether;
    uint public expiryCompensation = 0;

    function setMaxAttackers(uint8 _max) external onlyOwner {
        BattlePropertyChanged("Defender Fee", uint(maxAttackers), uint(_max));
        maxAttackers = _max;
    }

    function setMaxRevealTime(uint64 _maxRevealTime) external onlyOwner {
        BattlePropertyChanged("Reveal Time ", maxRevealTime, _maxRevealTime);
        maxRevealTime = _maxRevealTime;
    }

    function setAttackerFee(uint _fee) external onlyOwner {
        BattlePropertyChanged("Attacker Fee", attackerFee, _fee);
        attackerFee = _fee;
    }

    function setDefenderFee(uint _fee) external onlyOwner {
        BattlePropertyChanged("Defender Fee", defenderFee, _fee);
        defenderFee = _fee;
    }


    function setAttackerRefund(uint _refund) external onlyOwner {
        BattlePropertyChanged("Attacker Refund", expiryCompensation, _refund);
        expiryCompensation = _refund;
    }

    function _makePart(uint _id) internal view returns(EtherbotsBase.Part) {
        var (id, pt, pst, rarity, element, bld, exp, forgeTime, blr) = base.getPartById(_id);
        return EtherbotsBase.Part({
            tokenId: id,
            partType: pt,
            partSubType: pst,
            rarity: rarity,
            element: element,
            battlesLastDay: bld,
            experience: exp,
            forgeTime: forgeTime,
            battlesLastReset: blr
        });
    }

    /*
    =========================
    EXTERNAL BATTLE FUNCTIONS
    =========================
    */

    function createBattle(address _creator, uint[] _partIds, bytes32 _commit, uint _revealLength) external payable whenNotPaused { 

        require(msg.sender == address(base));

        for (uint i = 0; i < _partIds.length; i++) {
            base.takeOwnership(_partIds[i]);
        }

        _defenderCommitMoves(_creator, _partIds, _commit, _revealLength);
    }

    function _defenderCommitMoves(address _defender, 
        uint[] partIds, bytes32 _movesCommit, uint _revealLength) internal {
        require(_movesCommit != "");

        require(msg.value >= defenderFee);

        // check parts: defence1 melee2 body3 turret4
        // uint8[4] memory types = [1, 2, 3, 4];

        require(base.hasValidParts(partIds));
        require(_revealLength < maxRevealTime);

        Duel memory _duel = Duel({
            defenderAddress: _defender,
            defenderParts: partIds,
            defenderCommit: _movesCommit,
            revealTime: uint64(_revealLength),
            status: DuelStatus.Open,
            feeRemaining: msg.value
        });
        // TODO: -1 here?
        uint256 newDuelId = duels.push(_duel) - 1;
        // duelIdToAttackers[newDuelId] = new Attacker[](16);
        duelingPlayers++; // doesn't matter if we overcount
        // addressToDuels[msg.sender].push(newDuelId);
        BattleCreated(newDuelId, _defender);
    }

    function attack(uint _duelId, uint[] partIds, uint8[] _moves) external payable returns(bool) {

        // check that it's your robot
        require(base.ownsAll(msg.sender, partIds));
        // check parts submitted are valid
        require(base.hasValidParts(partIds));

        // check that the moves are readable
        require(_isValidMoves(_moves));

        Duel storage duel = duels[_duelId];
        // the duel must be open
        require(duel.status == DuelStatus.Open);
        // can't attack after reveal time (no free wins)
        // require(duel.revealTime >= now);
        require(duelIdToAttackers[_duelId].length < maxAttackers);
        require(msg.value >= attackerFee);

        // checks part independence and timing
        require(_canAttack(_duelId, partIds));

        if (duel.feeRemaining < defenderFee) {
            // just do a return - no need to punish the attacker
            // mark as exhausted
            duel.status = DuelStatus.Exhausted;
            return false;
        }


        duel.feeRemaining -= defenderFee;

        // already guaranteed
        Attacker memory _a = Attacker({
            owner: msg.sender,
            parts: partIds,
            moves: _moves,
            isWinner: false
        });

        // duelIdToAttackers[_duelId].push(_a);
        duelIdToAttackers[_duelId].push(_a);

        if (duelIdToAttackers[_duelId].length == maxAttackers) {
            duel.status = DuelStatus.Exhausted;
            duel.revealTime = uint64(now) + duel.revealTime;
            // update the new reveal time once final attacker attacks
        }

        // increment those battling - @rename
        duelingPlayers++;
        return true;
    }

    function _canAttack(uint _duelId, uint[] parts ) internal view returns(bool) {
        // short circuit if trying to attack yourself
        // obviously can easily get around this, but may as well check
        if (duels[_duelId].defenderAddress == msg.sender) {
            return false;
        }
        // the same part cannot attack the same bot at the same time
        for (uint i = 0; i < duelIdToAttackers[_duelId].length; i++) {
            for (uint j = 0; j < duelIdToAttackers[_duelId][i].parts.length; j++) {
                if (duelIdToAttackers[_duelId][i].parts[j] == parts[j]) {
                    return false;
                }
            }
        }
        return true;
    }

    uint8 constant MOVE_LENGTH = 5;

    function _isValidMoves(uint8[] _moves) internal pure returns(bool) {
        if (_moves.length != MOVE_LENGTH) {
            return false;
        }
        for (uint i = 0; i < MOVE_LENGTH; i++) {
            if (_moves[i] >= MOVE_TYPE_COUNT) {
                return false;
            }
        }
        return true;
    }

    event PrintMsg(string, address, address);

    function defenderRevealMoves(uint _duelId, uint8[] _moves, bytes32 _seed) external returns(bool) {
        require(duelIdToAttackers[_duelId].length != 0);

        Duel storage _duel = duels[_duelId];

        PrintMsg("reveal with defender", _duel.defenderAddress, msg.sender);

        require(_duel.defenderAddress == msg.sender);
        require(_duel.defenderCommit == keccak256(_moves, _seed));

        require(_duel.status == DuelStatus.Open || _duel.status == DuelStatus.Exhausted);

        if (!_isValidMoves(_moves)) {
            _forceAttackerWin(_duelId, _duel);
            _duel.status = DuelStatus.Completed;
            return false;
        }

        // after the defender has revealed their moves, perform all the duels
        EtherbotsBase.Part[4] memory defenderParts = [
            _makePart(_duel.defenderParts[0]),
            _makePart(_duel.defenderParts[1]),
            _makePart(_duel.defenderParts[2]),
            _makePart(_duel.defenderParts[3])
        ];

        Attacker[] storage attackers = duelIdToAttackers[_duelId];

        for (uint i = 0; i < attackers.length; i++) {
            _executeMoves(_duelId, attackers[i], defenderParts, _moves);
        }

        duelingPlayers -= (duelIdToAttackers[_duelId].length + 1);
        // give back an extra fees
        _refundDuelFee(_duel);
        // send back ownership of parts
        base.transferAll(_duel.defenderAddress, _duel.defenderParts);
        duels[_duelId].status = DuelStatus.Completed;

        return true;
    }

    // should only be used where the defender has forgotten their moves
    // forfeits every battle
    function cancelBattle(uint _duelId) external {

        Duel storage _duel = duels[_duelId];

        // can only be called by the defender
        require(msg.sender == _duel.defenderAddress);

        _forceAttackerWin(_duelId, _duel);

        _duel.status = DuelStatus.Cancelled;
    }

    // after the time limit has elapsed, anyone can claim victory for all the attackers
    // have to pay gas cost for all
    function claimTimeVictory(uint _duelId) external {

        Duel storage _duel = duels[_duelId];

        // let anyone claim it to stop boring iteration

        require(_duel.status == DuelStatus.Exhausted);
        require(now > _duel.revealTime);

        // make sure there's at least one attacker
        require(duelIdToAttackers[_duelId].length > 0);

        _forceAttackerWin(_duelId, _duel);

        _duel.status = DuelStatus.Completed;
    }

    function _forceAttackerWin(uint _duelId, Duel storage _duel) internal {


        require(_duel.status == DuelStatus.Open || _duel.status == DuelStatus.Exhausted);

        for (uint i = 0; i < duelIdToAttackers[_duelId].length; i++) {
            Attacker memory tempA = duelIdToAttackers[_duelId][i];
            duelIdToAttackers[_duelId][i].isWinner = true;
            _forfeitBattle(tempA.owner, tempA.moves, tempA.parts, _duel.defenderParts);
        }
        // refund the defender

        _refundDuelFee(_duel);

        // transfer parts back to defender
        base.transferAll(_duel.defenderAddress, _duel.defenderParts);
    }

    function _refundDuelFee(Duel storage _duel) internal {
        if (_duel.feeRemaining > 0) {
            uint a = _duel.feeRemaining;
            _duel.feeRemaining = 0;
            _duel.defenderAddress.transfer(a);
        }
    }

    uint16 constant EXP_BASE = 100;
    uint16 constant WINNER_EXP = 3;
    uint16 constant LOSER_EXP = 1;

    uint8 constant BONUS_PERCENT = 5;
    uint8 constant ALL_BONUS = 5;

    function _getElementBonus(uint movingPart, EtherbotsBase.Part[4] parts) internal view returns (uint8) {
        uint8 typ = parts[movingPart].element;
        // apply bonuses
        uint8 matching = 0;
        for (uint8 i = 0; i < parts.length; i++) {
            if (parts[i].element == typ) {
                matching++;
            }
        }
        // matching will never be less than 1
        uint8 bonus = (matching - 1) * BONUS_PERCENT;
        return bonus;
    }

    uint8 constant PERK_BONUS = 5;
    uint8 constant PRESTIGE_INC = 1;

    uint8 constant PT_PRESTIGE_INDEX = 0;
   
    bytes4 constant moveToPT = 0x06050304;
    bytes4 constant elementToPT = 0x05060403;
    uint8 constant PRESTIGE_BONUS = 1;

    function _applyBonusTree(uint8 move, EtherbotsBase.Part[4] parts, uint8[32] tree) internal pure returns (uint8 bonus) {
        uint8 prestige = tree[PT_PRESTIGE_INDEX];
        
        uint8 active = 0;
        uint8 level2 = uint8(moveToPT[move]);
        uint8 level1 = (level2 - 1) / 2;
        
        if (tree[level1] > 0) {
            active++;
            if (tree[level2] > 0) {
                active++;
                
                uint8 level4 = level2 * 4 + uint8(elementToPT[parts[move].element]);
                uint8 level3 = (level4 - 1) / 2;
                
                if (tree[level3] > 0) {
                    active++;
                    if (tree[level4] > 0) {
                        active++;
                    }
                }
            }
        }
        bonus = active * (PERK_BONUS + (prestige * PRESTIGE_BONUS));
    }

    function getMoveType(EtherbotsBase.Part[4] parts, uint8 _move) internal pure returns(uint8) {
        return parts[_move].element;
    }

    function hasPerk(uint8[32] tree, uint8 perk) internal pure returns(bool) {
        return tree[perk] > 0;
    }

    // uint8 constant PRESTIGE_BONUS = 1;

    function _applyPerkBonus(uint8 bonus, uint8 prestige) internal pure returns (uint8) {
        return bonus + (PERK_BONUS + (prestige * PRESTIGE_BONUS));
    }

    function _getPerkBonus(uint8 move, EtherbotsBase.Part[4] parts) internal view returns (uint8) {
        var (, perks) = base.getUserByAddress(msg.sender);
        return _applyBonusTree(move, parts, perks);
    }

    uint8 constant EXP_BONUS = 1;
    uint8 constant EVERY_X_LEVELS = 2;

    function _getExpBonus(uint32 experience) internal view returns (uint8) {
        // could replicate locally but allow base contract to make updates
        return uint8((EXP_BONUS * base.getLevel(experience)) / EVERY_X_LEVELS);
    }

    uint8 constant STANDARD_RARITY = 1;
    uint8 constant SHADOW_RARITY = 2;
    uint8 constant GOLD_RARITY = 3;

    // allow for more rarities
    // might never implement: undroppable rarities
    // 5 gold parts can be forged into a diamond
    // assumes rarity as follows: standard = 0, shadow = 1, gold = 2
    // shadow gives base 5% boost, gold 10% ...
    function _getRarityBonus(uint8 move, EtherbotsBase.Part[4] parts) internal pure returns (uint8) {
        // bonus applies per part (but only if you're using the rare part in this move)
        uint8 rarity = parts[move].rarity;
        if (rarity == STANDARD_RARITY) {
            // standard rarity, no bonus
            return 0;
        }
        uint8 count = 0;
        // will always be at least 1
        for (uint8 i = 0; i < parts.length; i++) {
            if (parts[i].rarity == rarity) {
                count++;
            }
        }
        uint8 bonus = (rarity - 1) * count * BONUS_PERCENT;
        return bonus;
    }

    function _applyBonuses(uint8 move, EtherbotsBase.Part[4] parts, uint16 _dmg) internal view returns(uint16) {
        // perks only land if you won the move
        uint16 _bonus = 0;
        _bonus += _getPerkBonus(move, parts);
        _bonus += _getElementBonus(move, parts);
        _bonus += _getExpBonus(parts[move].experience);
        _bonus += _getRarityBonus(move, parts);
        _dmg += (_dmg * _bonus) / 100;
        return _dmg;
    }

    // what about collusion - can try to time the block?
    // obviously if colluding could just pick exploitable moves
    // this is random enough for two non-colluding parties
    function randomSeed(uint8[] defenderMoves, uint8[] attackerMoves, uint8 rand) internal pure returns (uint) {
        return uint(keccak256(defenderMoves, attackerMoves, rand));
        // return random;
    }

    event attackerdamage(uint16 dam);
    event defenderdamage(uint16 dam);

    function _executeMoves(uint _duelId, Attacker storage attacker,
        EtherbotsBase.Part[4] defenderParts, uint8[] _defenderMoves) internal {
        // @fixme change usage of seed to make sure it's okay.
        //  uint seed = randomSeed(_defenderMoves, attacker.moves);
        uint16 totalAttackerDamage = 0;
        uint16 totalDefenderDamage = 0;

        EtherbotsBase.Part[4] memory attackerParts = [
            _makePart(attacker.parts[0]),
            _makePart(attacker.parts[1]),
            _makePart(attacker.parts[2]),
            _makePart(attacker.parts[3])
        ];

        uint16 attackerDamage;
        uint16 defenderDamage;
        // works just the same for draws
        for (uint8 i = 0; i < MOVE_LENGTH; i++) {
           // TODO: check move for validity?
            // var attackerMove = attacker.moves[i];
            // var defenderMove = _defenderMoves[i];
            (attackerDamage, defenderDamage) = _calculateBaseDamage(attacker.moves[i], _defenderMoves[i]);

            attackerDamage = _applyBonuses(attacker.moves[i], attackerParts, attackerDamage);
            defenderDamage = _applyBonuses(_defenderMoves[i], defenderParts, defenderDamage);
            attackerdamage(attackerDamage);
            defenderdamage(defenderDamage);
            attackerDamage = _applyRandomness(randomSeed(_defenderMoves, attacker.moves, i + 8), attackerDamage);
            defenderDamage = _applyRandomness(randomSeed(_defenderMoves, attacker.moves, i), defenderDamage);

            totalAttackerDamage += attackerDamage;
            totalDefenderDamage += defenderDamage;
            attackerdamage(attackerDamage);
            defenderdamage(defenderDamage);
            BattleStage(_duelId, i, [ attacker.moves[i], _defenderMoves[i] ], [attackerDamage, defenderDamage]);
            // BattleStage(_duelId, i, movesInMemory, damageInMemory );
        }

        if (totalAttackerDamage > totalDefenderDamage) {
            attacker.isWinner = true;
        }
        _winBattle(duels[_duelId].defenderAddress, attacker.owner, _defenderMoves,
            attacker.moves, duels[_duelId].defenderParts, attacker.parts, attacker.isWinner);
    }

    uint constant RANGE = 40;

    function _applyRandomness(uint rand, uint16 _dmg) internal pure returns (uint16) {
        // damage can be modified between 1 - (RANGE/2) and 1 + (RANGE/2)
        // keep things interesting!
        int16 damageNoise = 0;
        rand = rand % RANGE;
        if (rand > (RANGE / 2)) {
            damageNoise = int16(rand/2);
            // rand is 21 or above
        } else {
            // rand is 20 or below
            // this way makes 0 better than 20 --> who cares
            damageNoise = int16(-rand);
        }
        int16 toChange = int16(_dmg) * damageNoise/100;
        return uint16(int16(_dmg) + toChange);
    }

    // every move
    uint16 constant BASE_DAMAGE = 1000;
    uint8 constant WINNER_SPLIT = 3;
    uint8 constant LOSER_SPLIT = 1;

    function _calculateBaseDamage(uint8 a, uint8 d) internal pure returns(uint16, uint16) {
        if (defeats(a, d)) {
            // 3 - 1 split
            return ((BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * WINNER_SPLIT,
               (BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * LOSER_SPLIT);
        } else if (defeats(d, a)) {
            // 3 - 1 split
            return ((BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * LOSER_SPLIT,
               (BASE_DAMAGE / (WINNER_SPLIT + LOSER_SPLIT)) * WINNER_SPLIT);
        } else {
            return (BASE_DAMAGE / 2, BASE_DAMAGE / 2);
        }
    }

    uint8 constant MOVE_TYPE_COUNT = 4;

    // defence > attack
    // attack > body
    // body > turret
    // turret > defence
    function defeats(uint8 a, uint8 b) internal pure returns(bool) {
        return (a + 1) % MOVE_TYPE_COUNT == b;
    }

    // Experience-related functions/fields
    function _winBattle(address attackerAddress, address defenderAddress,
        uint8[] attackerMoves, uint8[] defenderMoves, uint[] attackerPartIds,
        uint[] defenderPartIds, bool isAttackerWinner) internal {
        if (isAttackerWinner) {
            var (winnerExpBase, loserExpBase) = _calculateExpSplit(attackerPartIds, defenderPartIds);
            _allocateExperience(attackerAddress, attackerMoves, winnerExpBase, attackerPartIds);
            _allocateExperience(defenderAddress, defenderMoves, loserExpBase, defenderPartIds);
        } else {
            (winnerExpBase, loserExpBase) = _calculateExpSplit(defenderPartIds, attackerPartIds);
            _allocateExperience(defenderAddress, defenderMoves, winnerExpBase, defenderPartIds);
            _allocateExperience(attackerAddress, attackerMoves, loserExpBase, attackerPartIds);
        }
    }

    function _forfeitBattle(address winnerAddress,
        uint8[] winnerMoves, uint[] winnerPartIds, uint[] loserPartIds) internal {
        var (winnerExpBase, ) = _calculateExpSplit(winnerPartIds, loserPartIds);

        _allocateExperience(winnerAddress, winnerMoves, winnerExpBase, winnerPartIds);
    }

    uint16 constant BASE_EXP = 1000;
    uint16 constant EXP_MIN = 100;
    uint16 constant EXP_MAX = 1000;

    // this is a very important function in preventing collusion
    // works as a sort-of bell curve distribution
    // e.g. big bot attacks and defeats small bot (75exp, 25exp) = 100 total
    // e.g. big bot attacks and defeats big bot (750exp, 250exp) = 1000 total
    // e.g. small bot attacks and defeats big bot (1000exp, -900exp) = 100 total
    // huge incentive to play in the middle of the curve
    // makes collusion only slightly profitable (maybe -EV considering battle fees)
    function _calculateExpSplit(uint[] winnerParts, uint[] loserParts) internal view returns (int32, int32) {
        uint32 totalWinnerLevel = base.totalLevel(winnerParts);
        uint32 totalLoserLevel = base.totalLevel(loserParts);
        // TODO: do we care about gold parts/combos etc
        // gold parts will naturally tend to higher levels anyway
        int32 total = _calculateTotalExperience(totalWinnerLevel, totalLoserLevel);
        return _calculateSplits(total, totalWinnerLevel, totalLoserLevel);
    }

    int32 constant WMAX = 1000;
    int32 constant WMIN = 75;
    int32 constant LMAX = 250;
    int32 constant LMIN = -900;

    uint8 constant WS = 3;
    uint8 constant LS = 1;

    function _calculateSplits(int32 total, uint32 wl, uint32 ll) internal pure returns (int32, int32) {

        int32 winnerSplit = max(WMIN, min(WMAX, ((total * WS) * (int32(ll) / int32(wl))) / (WS + LS)));
        int32 loserSplit = total - winnerSplit;

        return (winnerSplit, loserSplit);
    }

    int32 constant BMAX = 1000;
    int32 constant BMIN = 100;
    int32 constant RATIO = BMAX / BMIN;

    // total exp generated follows a weird curve
    // 100 plays 1, wins: 75/25      -> 100
    // 50 plays 50, wins: 750/250    -> 1000
    // 1 plays 1, wins: 750/250      -> 1000
    // 1 plays 100, wins: 1000, -900 -> 100
    function _calculateTotalExperience(uint32 wl, uint32 ll)  internal pure returns (int32) {
        int32 diff = (int32(wl) - int32(ll));
        return max(BMIN, BMAX - max(-RATIO * diff, RATIO * diff));
    }

    function max(int32 a, int32 b) internal pure returns (int32) {
        if (a > b) {
            return a;
        }
        return b;
    }

    function min(int32 a, int32 b) internal pure returns (int32) {
        if (a > b) {
            return b;
        }
        return a;
    }

    // allocates experience based on how many times a part was used in battle
    function _allocateExperience(address playerAddress, uint8[] moves, int32 exp, uint[] partIds) internal {
        int32[] memory exps = new int32[](partIds.length);
        int32 each = exp / MOVE_LENGTH;
        for (uint i = 0; i < MOVE_LENGTH; i++) {
            exps[moves[i]] += each;
        }
        base.addExperience(playerAddress, partIds, exps);
    }


}
