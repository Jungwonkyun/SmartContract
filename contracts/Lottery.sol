pragma solidity >=0.4.21 <0.6.0;

contract Lottery {
    struct BetInfo {
        uint256 answerBlockNumber; // 맞추려고 하는 정답 블록의 넘버
        address payable bettor; // bettor에게 돈을 보내기 위해 payable이라는 수식어가 붙어야 transfer가 가능
        bytes1 challenges; // 0xab 1바이트 글자 이 값과 비교해서 정답확인
    }

    uint256 private _tail; //_bets의 tail값
    uint256 private _head; //_bets의 head값
    mapping(uint256 => BetInfo) private _bets; //BetInfo의 정보를 담고 있는 _bets라는 queue로 값이 들어온다

    address payable public owner; //스마트 컨트랙트 외부에서 owner값을 자동으로 확인

    uint256 private _pot; //팟 머니를 저장하는 변수
    bool private mode = false; // false : use answer for test , true : use real block hash
    bytes32 public answerForTest; // when false일 때 test용 hash 설정

    uint256 internal constant BLOCK_LIMIT = 256; //최대 256개의 블록해시값을 확인가능
    uint256 internal constant BET_BLOCK_INTERVAL = 3; // +3 번째 블록해시값을 예측할 것이기 때문  ex) 3번 블록에서 베팅 -> 6번 블록해시값 예측
    uint256 internal constant BET_AMOUNT = 5 * 10**15; //배팅금액 0.005 ETH 고정

    enum BlockStatus {
        Checkable,
        NotRevealed,
        BlockLimitPassed
    }
    enum BettingResult {
        Fail,
        Win,
        Draw
    }

    event BET(
        uint256 index,
        address bettor,
        uint256 amount,
        bytes1 challenges,
        uint256 answerBlockNumber
    );
    event WIN(
        uint256 index,
        address bettor,
        uint256 amount,
        bytes1 challenges,
        bytes1 answer,
        uint256 answerBlockNumber
    );
    event FAIL(
        uint256 index,
        address bettor,
        uint256 amount,
        bytes1 challenges,
        bytes1 answer,
        uint256 answerBlockNumber
    );
    event DRAW(
        uint256 index,
        address bettor,
        uint256 amount,
        bytes1 challenges,
        bytes1 answer,
        uint256 answerBlockNumber
    );
    event REFUND(
        uint256 index,
        address bettor,
        uint256 amount,
        bytes1 challenges,
        uint256 answerBlockNumber
    );

    // 배포가 될 때 보낸사람으로 owner를 저장하겠다라는 의미 initializer
    constructor() public {
        owner = msg.sender;
    }

    //smart contract의 변수를 주기 위해선 view를 사용해야한다.
    function getPot() public view returns (uint256 pot) {
        return _pot;
    }

    /**
     * @dev 베팅과 정답 체크를 한다. 유저는 0.005 ETH를 보내야 하고, 베팅용 1 byte 글자를 보낸다.
     * 큐에 저장된 베팅 정보는 이후 distribute 함수에서 해결된다.
     * @param challenges 유저가 베팅하는 글자
     * @return 함수가 잘 수행되었는지 확인해는 bool 값
     */
    function betAndDistribute(bytes1 challenges)
        public
        payable
        returns (bool result)
    {
        bet(challenges);

        distribute();

        return true;
    }

    // 90846 -> 75846
    /**
     * @dev 베팅을 한다. 유저는 0.005 ETH를 보내야 하고, 베팅용 1 byte 글자를 보낸다.
     * 큐에 저장된 베팅 정보는 이후 distribute 함수에서 해결된다.
     * @param challenges 유저가 베팅하는 글자
     * @return 함수가 잘 수행되었는지 확인해는 bool 값
     */
    function bet(bytes1 challenges) public payable returns (bool result) {
        //알맞은 ETH가 전송되었는지 확인
        require(msg.value == BET_AMOUNT, "Not enough ETH");

        //_bets queue에 bet값 enque
        require(pushBet(challenges), " add a new Bet Info");

        //event log를 기록하는 function
        emit BET(
            _tail - 1,
            msg.sender,
            msg.value,
            challenges,
            block.number + BET_BLOCK_INTERVAL
        );

        return true;
    }

    /**
     * @dev 베팅 결과값을 확인 하고 팟머니를 분배한다.
     * 정답 실패 : 팟머니 축척, 정답 맞춤 : 팟머니 획득, 한글자 맞춤 or 정답 확인 불가 : 베팅 금액만 획득
     */
    function distribute() public {
        //head 3 4 5 6 7 8 9 10 Betting 정보  if 3번을 확인 -> 정답? pot머니 지급 : pot머니에 저장
        //while 정답을 확인 할 수 없을때 (if 285 286 ....) -> 3번 블록 확인 X, 보낸 돈만 유저에게 지급
        uint256 cur;
        uint256 transferAmount;

        BetInfo memory b;
        BlockStatus currentBlockStatus;
        BettingResult currentBettingResult;

        for (cur = _head; cur < _tail; cur++) {
            b = _bets[cur];
            currentBlockStatus = getBlockStatus(b.answerBlockNumber);

            //Case1 Checkable:
            //block.number > answerBlockNumber && block.number < BLOCK_LIMIT + answerBlockNumber
            if (currentBlockStatus == BlockStatus.Checkable) {
                bytes32 answerBlockHash = getAnswerBlockHash(
                    b.answerBlockNumber
                );
                currentBettingResult = isMatch(b.challenges, answerBlockHash);
                // if win, bettor gets pot
                if (currentBettingResult == BettingResult.Win) {
                    // transfer pot
                    transferAmount = transferAfterPayingFee(
                        b.bettor,
                        _pot + BET_AMOUNT
                    );

                    // pot = 0
                    _pot = 0;

                    // emit WIN
                    emit WIN(
                        cur,
                        b.bettor,
                        transferAmount,
                        b.challenges,
                        answerBlockHash[0],
                        b.answerBlockNumber
                    );
                }
                // if fail, bettor's money goes pot
                if (currentBettingResult == BettingResult.Fail) {
                    // pot = pot + BET_AMOUNT
                    _pot += BET_AMOUNT;
                    // emit FAIL
                    emit FAIL(
                        cur,
                        b.bettor,
                        0,
                        b.challenges,
                        answerBlockHash[0],
                        b.answerBlockNumber
                    );
                }

                // if draw, refund bettor's money
                if (currentBettingResult == BettingResult.Draw) {
                    // transfer only BET_AMOUNT
                    transferAmount = transferAfterPayingFee(
                        b.bettor,
                        BET_AMOUNT
                    );

                    // emit DRAW
                    emit DRAW(
                        cur,
                        b.bettor,
                        transferAmount,
                        b.challenges,
                        answerBlockHash[0],
                        b.answerBlockNumber
                    );
                }
            }

            //Case2 Not Revealed 아직 블록이 mining 되지 읺았을 때
            //block.number <= answerBlockNumber 현재 mining중이거나 이전인 블록은 확인 할 수 없다
            if (currentBlockStatus == BlockStatus.NotRevealed) {
                break;
            }

            //Case3 Block Limit Passed 256개 이전에 mining된 블록을 확인할 때
            //block.number >= BLOCK_LIMIT + answerBlockNumber
            if (currentBlockStatus == BlockStatus.BlockLimitPassed) {
                // refund
                transferAmount = transferAfterPayingFee(b.bettor, BET_AMOUNT);
                // emit refund
                emit REFUND(
                    cur,
                    b.bettor,
                    transferAmount,
                    b.challenges,
                    b.answerBlockNumber
                );
            }
            //iteration 마지막에 cur block을 queue에서 pop 해준다
            popBet(cur);
        }
        //Not revealed 일때 head index를 바꾸어준다
        _head = cur;
    }

    function transferAfterPayingFee(address payable addr, uint256 amount)
        internal
        returns (uint256)
    {
        // uint256 fee = amount / 100;
        uint256 fee = 0;
        uint256 amountWithoutFee = amount - fee;

        // transfer to addr
        addr.transfer(amountWithoutFee);

        // transfer to owner
        owner.transfer(fee);

        // call, send, transfer -> trasnfer는 ETH만 던져주고 실패하면 transaction rejection 가장 안전하다.
        // 외부에 있는 smart contract를 함부로 호출하는 경우 call 문제가 발생할 수 있다.

        return amountWithoutFee;
    }

    //if test mode일 때 사용할 사용자 지정 해쉬값을 설정해준다.
    function setAnswerForTest(bytes32 answer) public returns (bool result) {
        //Only owner 에게만 test, real를 지정할 수 있는 권한을 준다.
        require(
            msg.sender == owner,
            "Only owner can set the answer for test mode"
        );
        answerForTest = answer;
        return true;
    }

    //true => real blockHash를 가져오고 false이면 우리가 지정한 Hash값을 사용하여 test한다
    function getAnswerBlockHash(uint256 answerBlockNumber)
        internal
        view
        returns (bytes32 answer)
    {
        return mode ? blockhash(answerBlockNumber) : answerForTest;
    }

    /**
     * @dev 베팅글자와 정답을 확인한다.
     * @param challenges 베팅 글자
     * @param answer 블락해쉬
     * @return 정답결과
     */
    function isMatch(bytes1 challenges, bytes32 answer)
        public
        pure
        returns (BettingResult)
    {
        // challenges 0xab
        // answer 0xab......ff 32 bytes

        bytes1 c1 = challenges;
        bytes1 c2 = challenges;

        bytes1 a1 = answer[0];
        bytes1 a2 = answer[0];

        // Get first number
        c1 = c1 >> 4; // 0xab -> 0x0a
        c1 = c1 << 4; // 0x0a -> 0xa0

        a1 = a1 >> 4;
        a1 = a1 << 4;

        // Get Second number
        c2 = c2 << 4; // 0xab -> 0xb0
        c2 = c2 >> 4; // 0xb0 -> 0x0b

        a2 = a2 << 4;
        a2 = a2 >> 4;

        if (a1 == c1 && a2 == c2) {
            return BettingResult.Win;
        }

        if (a1 == c1 || a2 == c2) {
            return BettingResult.Draw;
        }

        return BettingResult.Fail;
    }

    //현재 블록의 status를 확인하고 case 1,2,3별로 나누어서 BlockStatus를 Enum value로 return
    function getBlockStatus(uint256 answerBlockNumber)
        internal
        view
        returns (BlockStatus)
    {
        if (
            block.number > answerBlockNumber &&
            block.number < BLOCK_LIMIT + answerBlockNumber
        ) {
            return BlockStatus.Checkable;
        }

        if (block.number <= answerBlockNumber) {
            return BlockStatus.NotRevealed;
        }

        if (block.number >= answerBlockNumber + BLOCK_LIMIT) {
            return BlockStatus.BlockLimitPassed;
        }

        return BlockStatus.BlockLimitPassed;
    }

    // 우리가 원하는 index의 betting 정보를 얻을 때 사용하는 function
    function getBetInfo(uint256 index)
        public
        view
        returns (
            uint256 answerBlockNumber,
            address bettor,
            bytes1 challenges
        )
    {
        BetInfo memory b = _bets[index];
        answerBlockNumber = b.answerBlockNumber;
        bettor = b.bettor;
        challenges = b.challenges;
    }

    //_bets로 새로운 bet객체가 들어올 떄 관련 데이터를 업데이트 해주고 indexing을 늘려주는 function
    function pushBet(bytes1 challenges) internal returns (bool) {
        BetInfo memory b;
        b.bettor = msg.sender; // 20 byte
        b.answerBlockNumber = block.number + BET_BLOCK_INTERVAL; // 32byte  20000 gas
        b.challenges = challenges; // byte // 20000 gas

        _bets[_tail] = b;
        _tail++; // 32byte 값 변화 // 20000 gas -> 5000 gas

        return true;
    }

    //_bets 안에서 주어진 index의 정보값을 pop 할 때 사용하는 function
    function popBet(uint256 index) internal returns (bool) {
        delete _bets[index];
        return true;
    }
}
