const shouldFail = require('openzeppelin-solidity/test/helpers/shouldFail');
const expectEvent = require('openzeppelin-solidity/test/helpers/expectEvent');

const { advanceBlock } = require('openzeppelin-solidity/test/helpers/advanceToBlock');
const { ether } = require('openzeppelin-solidity/test/helpers/ether');

require('chai')
    .use(require('chai-as-promised'))
    .use(require('chai-bignumber')(web3.BigNumber))
    .should();

const SX = artifacts.require('SX');

contract('SX', function ([_, wallet1, wallet2, wallet3, wallet4, wallet5]) {
    beforeEach(async function () {
        await advanceBlock();
        this.sx = await SX.new();
        await this.sx.setMaxRewardPercent(100);
        await this.sx.putToBank({ value: ether(5) });
    });

    describe('play', async function () {
        describe('fail', async function () {
            it('should fail for combinations = 0', async function () {
                await shouldFail.reverting(
                    this.sx.play(0, 1, { value: ether(1) })
                );
            });

            it('should fail for combinations = 1', async function () {
                await shouldFail.reverting(
                    this.sx.play(1, 1, { value: ether(1) })
                );
            });

            it('should fail for combinations = 2 and answer = 0', async function () {
                await shouldFail.reverting(
                    this.sx.play(2, 0, { value: ether(1) })
                );
            });

            it('should fail for combinations = 2 and answer = 3', async function () {
                await shouldFail.reverting(
                    this.sx.play(2, 3, { value: ether(1) })
                );
            });

            it('should fail for combinations = 2 and answer = 4', async function () {
                await shouldFail.reverting(
                    this.sx.play(2, 4, { value: ether(1) })
                );
            });

            it('should fail for combinations = 101 and answer = 1', async function () {
                await shouldFail.reverting(
                    this.sx.play(101, 1, { value: ether(1) })
                );
            });

            it('should fail for large value', async function () {
                await shouldFail.reverting(
                    this.sx.play(2, 1, { value: ether(3) })
                );
            });
        });

        it('should work for coin', async function () {
            await this.sx.play(2, 1, { value: ether(1) });
            await advanceBlock();
            await advanceBlock();

            expectEvent.inTransaction(
                this.sx.finishAllGames(),
                'GameFinished',
                {
                    player: _,
                }
            );
        });

        it('should automatically continue previous games', async function () {
            await this.sx.play(2, 1, { value: ether(1) });
            await advanceBlock();
            await advanceBlock();

            expectEvent.inTransaction(
                this.sx.finishAllGames(),
                'GameFinished',
                {
                    player: _,
                }
            );
        });

        it('should have 50% probability to win', async function () {
            for (let i = 0; i < 100; i++) {
                await this.sx.play(2, 1, { value: ether(0.1) });
                await advanceBlock();
            }

            await advanceBlock();
            await advanceBlock();
            await this.sx.finishAllGames();
        });
    });
});
