const assert = require('chai').assert; 

//logs event에 베팅로그 들을 저장한다  찾고자 하는 string을 eventName에 넣어준다 
//if BET이라는 문자열이 없다면 Error를 출력한다. 
const inLogs = async (logs,eventName) =>{
    const event = logs.find(e => e.event === eventName)
    assert.exists(event);
}

module.exports = {
    inLogs

}