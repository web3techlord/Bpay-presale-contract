// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract BSCTMMPreSale is Ownable, Pausable, ReentrancyGuard {
    uint256 public totalTokensSold = 0;
    uint256 public totalUsdRaised = 0;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public claimStart;
    uint256 public constant baseDecimals = (10 ** 18);
    uint256 public maxTokensToBuy = 50_000_000;
    uint256 public minUsdAmountToBuy = 24900000000000000000;
    uint256 public currentStage = 0;
    uint256 public checkPoint = 0;
    uint256 public maxSlippageAmount = 10;

    uint256[][3] public stages;

    address public saleTokenAdress;
    address public constant recipientETHAddress = 0x0262D76db6A28eFadfdD9bD2538Bf10ead9c160E;
    address public constant recipientUSDTAddress = 0x3EF7a84C338e050ed63513ec5e6C6E450601bd12;

    IERC20 public USDTInterface =
        IERC20(0x55d398326f99059fF775485246999027B3197955);
    AggregatorV3Interface internal priceFeed =
        AggregatorV3Interface(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE);

    mapping(address => uint256) public userDeposits;
    mapping(address => bool) public hasClaimed;

    event SaleTimeSet(uint256 _start, uint256 _end, uint256 timestamp);
    event SaleTimeUpdated(
        bytes32 indexed key,
        uint256 prevValue,
        uint256 newValue,
        uint256 timestamp
    );
    event TokensBought(
        address indexed user,
        uint256 indexed tokensBought,
        address indexed purchaseToken,
        uint256 amountPaid,
        uint256 usdEq,
        uint256 timestamp
    );
    event TokensAdded(
        address indexed token,
        uint256 noOfTokens,
        uint256 timestamp
    );
    event TokensClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event ClaimStartUpdated(
        uint256 prevValue,
        uint256 newValue,
        uint256 timestamp
    );
    event CurrentStageUpdated(
        uint256 prevValue,
        uint256 newValue,
        uint256 timestamp
    );

    /**
     * @dev Initializes the contract and sets key parameters
     * @param _startTime start time of the presale
     * @param _endTime end time of the presale
     * @param _stages stage data
     */
    constructor(
        uint256 _startTime,
        uint256 _endTime,
        uint256[][3] memory _stages
    ) Ownable(msg.sender) {
        require(
            _startTime > block.timestamp && _endTime > _startTime,
            "Invalid time"
        );
        startTime = _startTime;
        endTime = _endTime;
        stages = _stages;
        emit SaleTimeSet(startTime, endTime, block.timestamp);
    }

    /**
     * @dev To pause the presale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev To unpause the presale
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev To change maxTokensToBuy amount
     * @param _maxTokensToBuy New max token amount
     */
    function changeMaxTokensToBuy(uint256 _maxTokensToBuy) external onlyOwner {
        require(_maxTokensToBuy > 0, "Zero max tokens to buy value");
        maxTokensToBuy = _maxTokensToBuy;
    }

    /**
     * @dev To change minUsdAmountToBuy. If zero, there is no min limit.
     * @param _minUsdAmount New min USD amount
     */
    function changeMinUsdAmountToBuy(uint256 _minUsdAmount) external onlyOwner {
        minUsdAmountToBuy = _minUsdAmount;
    }

    /**
     * @dev To change stages data
     * @param _stages New stage data
     */
    function changeStages(uint256[][3] memory _stages) external onlyOwner {
        stages = _stages;
    }

    /**
     * @dev To change maxSlippageAmount data
     * @param _maxSlippageAmount New maxSlippageAmount data
     */
    function changeMaxSlippageAmount(
        uint256 _maxSlippageAmount
    ) external onlyOwner {
        maxSlippageAmount = _maxSlippageAmount;
    }

    /**
     * @dev To change USDT interface
     * @param _address Address of the USDT interface
     */
    function changeUSDTInterface(address _address) external onlyOwner {
        USDTInterface = IERC20(_address);
    }

    /**
     * @dev To change aggregator interface
     * @param _address Address of the aggregator interface
     */
    function changeAggregatorInterface(address _address) external onlyOwner {
        priceFeed = AggregatorV3Interface(_address);
    }

    modifier checkSaleState(uint256 amount) {
        require(
            block.timestamp >= startTime && block.timestamp <= endTime,
            "Invalid time for buying"
        );
        require(amount > 0, "Invalid sale amount");
        _;
    }

    /**
     * @dev To calculate the price in USD for given amount of tokens.
     * @param _amount No of tokens
     */
    function calculatePrice(uint256 _amount) public view returns (uint256) {
        uint256 USDTAmount;
        uint256 total = checkPoint == 0 ? totalTokensSold : checkPoint;
        require(_amount <= maxTokensToBuy, "Amount exceeds max tokens to buy");
        if (
            _amount + total > stages[0][currentStage] ||
            block.timestamp >= stages[2][currentStage]
        ) {
            require(currentStage < (stages[0].length - 1), "Not valid");
            if (block.timestamp >= stages[2][currentStage]) {
                require(
                    stages[0][currentStage] + _amount <=
                        stages[0][currentStage + 1],
                    ""
                );
                USDTAmount = _amount * stages[1][currentStage + 1];
            } else {
                uint256 tokenAmountForCurrentPrice = stages[0][currentStage] -
                    total;
                USDTAmount =
                    tokenAmountForCurrentPrice *
                    stages[1][currentStage] +
                    (_amount - tokenAmountForCurrentPrice) *
                    stages[1][currentStage + 1];
            }
        } else USDTAmount = _amount * stages[1][currentStage];
        return USDTAmount;
    }

    /**
     * @dev To update the sale times
     * @param _startTime New start time
     * @param _endTime New end time
     */
    function changeSaleTimes(
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        require(_startTime > 0 || _endTime > 0, "Invalid parameters");
        if (_startTime > 0) {
            uint256 prevValue = startTime;
            startTime = _startTime;
            emit SaleTimeUpdated(
                bytes32("START"),
                prevValue,
                _startTime,
                block.timestamp
            );
        }

        if (_endTime > 0) {
            uint256 prevValue = endTime;
            endTime = _endTime;
            emit SaleTimeUpdated(
                bytes32("END"),
                prevValue,
                _endTime,
                block.timestamp
            );
        }
    }

    /**
     * @dev To get latest ETH price in 10**18 format
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        price = (price * (10 ** 10));
        return uint256(price);
    }

    /**
     * @dev To buy into a presale using USDT
     * @param amount No of tokens to buy
     */
    function buyWithUSDT(
        uint256 amount
    ) external checkSaleState(amount) whenNotPaused returns (bool) {
        uint256 usdPrice = calculatePrice(amount);

        uint256 ourAllowance = USDTInterface.allowance(
            _msgSender(),
            address(this)
        );
        uint256 price = usdPrice;
        require(price <= ourAllowance, "Not enough allowance");
        (bool success, ) = address(USDTInterface).call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                _msgSender(),
                recipientUSDTAddress,
                price
            )
        );
        require(success, "Token payment failed");

        totalTokensSold += amount;
        if (checkPoint != 0) checkPoint += amount;
        uint256 total = totalTokensSold > checkPoint
            ? totalTokensSold
            : checkPoint;
        if (
            total > stages[0][currentStage] ||
            block.timestamp >= stages[2][currentStage]
        ) {
            if (block.timestamp >= stages[2][currentStage]) {
                checkPoint = stages[0][currentStage] + amount;
            }
            currentStage += 1;

            emit CurrentStageUpdated(
                currentStage - 1,
                currentStage,
                block.timestamp
            );
        }
        userDeposits[_msgSender()] += (amount * baseDecimals);
        totalUsdRaised += usdPrice;

        emit TokensBought(
            _msgSender(),
            amount,
            address(USDTInterface),
            usdPrice,
            usdPrice,
            block.timestamp
        );
        return true;
    }

    /**
     * @dev To calculate the amount of tokens buyable with given ETH amount
     * @param ethAmount ETH amount in wei
     */
    function calculateAmount(uint256 ethAmount) public view returns (uint256) {
        uint256 ethPriceInUsd = (ethAmount * getLatestPrice()) / baseDecimals;

        uint256 total = checkPoint == 0 ? totalTokensSold : checkPoint;
        uint256 remainingTokensInStage = stages[0][currentStage] - total;
        uint256 usdAmountForRemainingTokens = remainingTokensInStage *
            stages[1][currentStage];

        uint256 tokenAmount;

        if (
            ethPriceInUsd > usdAmountForRemainingTokens ||
            block.timestamp >= stages[2][currentStage]
        ) {
            require(currentStage < (stages[0].length - 1), "Not valid");
            if (block.timestamp >= stages[2][currentStage]) {
                tokenAmount = ethPriceInUsd / stages[1][currentStage + 1];
            } else {
                tokenAmount =
                    remainingTokensInStage +
                    (ethPriceInUsd - usdAmountForRemainingTokens) /
                    stages[1][currentStage + 1];
            }
        } else {
            tokenAmount = ethPriceInUsd / stages[1][currentStage];
        }

        return tokenAmount;
    }

    /**
     * @dev To buy into a presale using ETH with slippage
     * @param amount No of tokens to buy
     * @param slippage Acceptable slippage percentage (0-100)
     */
    function buyWithEth(
        uint256 amount,
        uint256 slippage
    )
        external
        payable
        checkSaleState(amount)
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        require(amount <= maxTokensToBuy, "Amount exceeds max tokens to buy");
        require(slippage >= 0, "Slippage must bigger than 0");
        require(slippage <= maxSlippageAmount, "MaxSlippageAmount exceeds");

        uint256 ethAmount = msg.value;
        uint256 calculatedAmount = calculateAmount(ethAmount);
        require(
            calculatedAmount >= (amount * (100 - slippage)) / 100,
            "Slippage tolerance exceeded"
        );
        uint256 usdPrice = (ethAmount * getLatestPrice()) / baseDecimals;

        sendValue(payable(recipientETHAddress), ethAmount);

        totalTokensSold += calculatedAmount;
        if (checkPoint != 0) checkPoint += calculatedAmount;
        uint256 total = totalTokensSold > checkPoint
            ? totalTokensSold
            : checkPoint;
        if (
            total > stages[0][currentStage] ||
            block.timestamp >= stages[2][currentStage]
        ) {
            if (block.timestamp >= stages[2][currentStage]) {
                checkPoint = stages[0][currentStage] + calculatedAmount;
            }
            currentStage += 1;

            emit CurrentStageUpdated(
                currentStage - 1,
                currentStage,
                block.timestamp
            );
        }
        userDeposits[_msgSender()] += (calculatedAmount * baseDecimals);
        totalUsdRaised += usdPrice;

        emit TokensBought(
            _msgSender(),
            calculatedAmount,
            address(0),
            ethAmount,
            usdPrice,
            block.timestamp
        );
        return true;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Low balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH Payment failed");
    }

    /**
     * @dev To set the claim start time and sale token address by the owner
     * @param _claimStart claim start time
     * @param noOfTokens Number of tokens to add to the contract
     * @param _saleTokenAdress sale token address
     */
    function startClaim(
        uint256 _claimStart,
        uint256 noOfTokens,
        address _saleTokenAdress
    ) external onlyOwner returns (bool) {
        require(
            _claimStart > endTime && _claimStart > block.timestamp,
            "Invalid claim start time"
        );
        require(
            noOfTokens >= (totalTokensSold * baseDecimals),
            "Tokens less than sold"
        );
        require(_saleTokenAdress != address(0), "Zero token address");
        require(claimStart == 0, "Claim already set");
        claimStart = _claimStart;
        saleTokenAdress = _saleTokenAdress;
        bool success = IERC20(_saleTokenAdress).transferFrom(
            _msgSender(),
            address(this),
            noOfTokens
        );
        require(success, "Token transfer failed");
        emit TokensAdded(saleTokenAdress, noOfTokens, block.timestamp);
        return true;
    }

    /**
     * @dev To change the claim start time by the owner
     * @param _claimStart new claim start time
     */
    function changeClaimStartTime(
        uint256 _claimStart
    ) external onlyOwner returns (bool) {
        require(claimStart > 0, "Initial claim data not set");
        require(_claimStart > endTime, "Sale in progress");
        require(_claimStart > block.timestamp, "Claim start in past");
        uint256 prevValue = claimStart;
        claimStart = _claimStart;
        emit ClaimStartUpdated(prevValue, _claimStart, block.timestamp);
        return true;
    }

    /**
     * @dev To claim tokens after claiming starts
     */
    function claim() external whenNotPaused returns (bool) {
        require(saleTokenAdress != address(0), "Sale token not added");
        require(block.timestamp >= claimStart, "Claim has not started yet");
        require(!hasClaimed[_msgSender()], "Already claimed");
        hasClaimed[_msgSender()] = true;
        uint256 amount = userDeposits[_msgSender()];
        require(amount > 0, "Nothing to claim");
        delete userDeposits[_msgSender()];
        bool success = IERC20(saleTokenAdress).transfer(_msgSender(), amount);
        require(success, "Token transfer failed");
        emit TokensClaimed(_msgSender(), amount, block.timestamp);
        return true;
    }

    /**
     * @dev To manualy change stage
     */
    function changeCurrentStage(uint256 _currentStage) external onlyOwner {
        if (_currentStage > 0) {
            checkPoint = stages[0][_currentStage - 1];
        }
        currentStage = _currentStage;
    }

    /**
     * @dev Helper funtion to get stage information
     */
    function getStages() external view returns (uint256[][3] memory) {
        return stages;
    }

    function manualBuy(address _to, uint256 amount) external onlyOwner {
        uint256 usdPrice = calculatePrice(amount);
        totalTokensSold += amount;
        userDeposits[_to] += (amount * baseDecimals);
        totalUsdRaised += usdPrice;
    }
}
