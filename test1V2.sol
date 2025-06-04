// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IPancakePair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract SwapViaFactory {
    address public constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73; // BSC Mainnet
    address public constant WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB

    function buyToken(
        uint amountOut,     
        address token,      
        address recipient    
    ) external payable {
        address pair = IPancakeFactory(FACTORY).getPair(WETH, token);
        require(pair != address(0), "Pair not exists");

        bool isToken0 = WETH < token;
        (uint reserveIn, uint reserveOut) = _getReserves(pair, isToken0);

        uint amountIn = _calculateAmountIn(amountOut, reserveIn, reserveOut);
        require(msg.value >= amountIn, "Insufficient ETH");

        IWETH(WETH).deposit{value: amountIn}();
        IWETH(WETH).transfer(pair, amountIn);

        uint amount0Out = isToken0 ? 0 : amountOut;
        uint amount1Out = isToken0 ? amountOut : 0;
        IPancakePair(pair).swap(amount0Out, amount1Out, recipient, new bytes(0));

        if (msg.value > amountIn) {
            (bool success,) = payable(msg.sender).call{value: msg.value - amountIn}("");
            require(success, "ETH refund failed");
        }
    }

    function _getReserves(address pair, bool isToken0) private view returns (uint reserveIn, uint reserveOut) {
        (uint reserve0, uint reserve1,) = IPancakePair(pair).getReserves();
        (reserveIn, reserveOut) = isToken0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _calculateAmountIn(uint amountOut, uint reserveIn, uint reserveOut) private pure returns (uint) {
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    receive() external payable {}
}
