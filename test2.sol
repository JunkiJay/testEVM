// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPancakeRouter {
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
}

contract LiquidityManager {
    address public immutable ROUTER;
    address public immutable WETH;
    
    constructor(address _router, address _weth) {
        ROUTER = _router;
        WETH = _weth;
    }

    function buyTokenAndAddLiquidity(
        uint exactTokenAmount,  
        address token,           
        uint minLiquidityToken,  
        uint minLiquidityETH,    
        uint deadline         
    ) external payable {
        require(deadline > block.timestamp, "DEADLINE_EXCEEDED");
        
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        uint[] memory swapAmounts = IPancakeRouter(ROUTER).swapETHForExactTokens{value: msg.value}(
            exactTokenAmount,
            path,
            address(this), 
            deadline
        );
        
        uint ethUsed = swapAmounts[0];
        uint ethRemaining = msg.value - ethUsed;

        IERC20(token).approve(ROUTER, exactTokenAmount);
        
        (uint amountToken, uint amountETH, ) = IPancakeRouter(ROUTER).addLiquidityETH{value: ethRemaining}(
            token,
            exactTokenAmount,    
            minLiquidityToken,  
            minLiquidityETH,    
            msg.sender,      
            deadline
        );
        
        _refundRemaining(
            token, 
            exactTokenAmount - amountToken, 
            ethRemaining - amountETH
        );
    }

    function _refundRemaining(
        address token, 
        uint tokenDust, 
        uint ethDust
    ) private {
        if (ethDust > 0) {
            (bool success, ) = msg.sender.call{value: ethDust}("");
            require(success, "ETH_REFUND_FAILED");
        }
        
        if (tokenDust > 0) {
            require(IERC20(token).transfer(msg.sender, tokenDust), "TOKEN_REFUND_FAILED");
        }
    }

    receive() external payable {}
}
