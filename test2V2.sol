// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function balanceOf(address account) external view returns (uint);
}

interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IPancakePair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function mint(address to) external returns (uint liquidity);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function sync() external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
}

contract DirectLiquidityManager {
    address public immutable factory;
    address public immutable WETH;
    
    constructor(address _factory, address _weth) {
        factory = _factory;
        WETH = _weth;
    }

    function buyTokenAndAddLiquidity(
        uint exactTokenAmount,
        address token,
        uint minLiquidityToken,
        uint minLiquidityETH,
        uint deadline
    ) external payable {
        require(deadline >= block.timestamp, "DEADLINE_EXPIRED");
        
        address pair = IPancakeFactory(factory).getPair(WETH, token);
        require(pair != address(0), "NO_LIQUIDITY_POOL");
        
        (uint amountIn, bool isToken0) = calculateETHRequired(pair, token, exactTokenAmount);
        require(msg.value >= amountIn, "INSUFFICIENT_ETH");
        
        IWETH(WETH).deposit{value: amountIn}();
        IWETH(WETH).transfer(pair, amountIn);
        
        swapTokens(pair, token, exactTokenAmount, isToken0);
        
        uint ethRemaining = msg.value - amountIn;
        addLiquidityDirect(
            pair,
            token,
            exactTokenAmount,
            ethRemaining,
            minLiquidityToken,
            minLiquidityETH
        );
        
        refundDust(token);
    }

    function calculateETHRequired(
        address pair,
        address token,
        uint amountOut
    ) private view returns (uint amountIn, bool isToken0) {
        isToken0 = IPancakePair(pair).token0() == WETH;
        
        (uint reserve0, uint reserve1, ) = IPancakePair(pair).getReserves();
        (uint reserveIn, uint reserveOut) = isToken0 ? (reserve0, reserve1) : (reserve1, reserve0);
        
        uint numerator = reserveIn * amountOut * 10000;
        uint denominator = (reserveOut - amountOut) * 9975;
        amountIn = (numerator / denominator) + 1;
    }

    function swapTokens(
        address pair,
        address token,
        uint amountOut,
        bool isToken0
    ) private {
        uint amount0Out = isToken0 ? 0 : amountOut;
        uint amount1Out = isToken0 ? amountOut : 0;
        
        IPancakePair(pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            new bytes(0)
        );
    }

    function addLiquidityDirect(
        address pair,
        address token,
        uint tokenAmount,
        uint ethAmount,
        uint minTokenAmount,
        uint minETHAmount
    ) private {
        (uint reserve0, uint reserve1, ) = IPancakePair(pair).getReserves();
        bool isToken0 = IPancakePair(pair).token0() == token;
        (uint reserveETH, uint reserveToken) = isToken0 ? (reserve1, reserve0) : (reserve0, reserve1);

        uint optimalETHAmount;
        uint optimalTokenAmount;
        
        if (reserveETH == 0 || reserveToken == 0) {
            optimalETHAmount = ethAmount;
            optimalTokenAmount = tokenAmount;
        } else {
            uint ethRequired = (tokenAmount * reserveETH) / reserveToken;
            
            if (ethRequired <= ethAmount) {
                optimalTokenAmount = tokenAmount;
                optimalETHAmount = ethRequired;
            } else {
                optimalETHAmount = ethAmount;
                optimalTokenAmount = (ethAmount * reserveToken) / reserveETH;
            }
        }
        
        require(optimalTokenAmount >= minTokenAmount, "INSUFFICIENT_TOKEN_AMOUNT");
        require(optimalETHAmount >= minETHAmount, "INSUFFICIENT_ETH_AMOUNT");
        
        IWETH(WETH).deposit{value: optimalETHAmount}();
        IWETH(WETH).transfer(pair, optimalETHAmount);
        
        IERC20(token).transfer(pair, optimalTokenAmount);
        
        IPancakePair(pair).mint(msg.sender);
        
        IPancakePair(pair).sync();
    }

    function refundDust(address token) private {
        uint ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = msg.sender.call{value: ethBalance}("");
            require(success, "ETH_REFUND_FAILED");
        }
        
        uint tokenBalance = IERC20(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            IERC20(token).transfer(msg.sender, tokenBalance);
        }
        
        uint wethBalance = IWETH(WETH).balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(WETH).transfer(msg.sender, wethBalance);
        }
    }

    receive() external payable {}
}
