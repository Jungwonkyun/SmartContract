//lotery.test.js에서 받은 betting 정보 (ETh가 부족한)를 받아서 try catch문을 통해서 처리해준다 
module.exports = async (promise) => {
    try {
        await promise;
        assert.fail('Expected revert not received');
    } catch (error) {
        const revertFound = error.message.search('revert') >= 0;
        assert(revertFound, `Expected "revert", got ${error} instead`);
    }
}