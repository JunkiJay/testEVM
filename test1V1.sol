// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPancakeRouter {
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
}

contract SwapViaRouter {
    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // BSC Mainnet
    address public constant WETH = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // WBNB

    function buyToken(
        uint amountOut,  
        address token,       
        address recipient,   
        uint deadline       
    ) external payable {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        IPancakeRouter(ROUTER).swapETHForExactTokens{value: msg.value}(
            amountOut,
            path,
            recipient,
            deadline
        );

        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "ETH refund failed");
    }

    receive() external payable {}
}
