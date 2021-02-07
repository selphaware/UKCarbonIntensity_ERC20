/**
 * (C) Selphaware
 * 
 * UK Carbon Intensity (Ethereum Coin) Token.
 * 
 * Tracks UK Carbon intensity via Official Carbon Intensity API for Great Britain developed by National Grid. 
 * You can find out more about carbon intensity at carbonintensity.org.uk.
 * 
 * Carbon Intensity is measured in gCO2/kWh
 * e.g. 
 *      Hydroelectric	reservoir	~ 4 gCO2/kWh
 *      Wind	onshore	~ 12 gCO2/kWh
 *      Nuclear	various generation II reactor types	 ~ 16 gCO2/kWh
 *      Solar thermal	parabolic trough	~ 22 gCO2/kWh
 *      Geothermal	hot dry rock	~ 45 gCO2/kWh
 *      Solar PV	Polycrystalline silicon	~ 46 gCO2/kWh
 *      Biomass	various	~ 230 gCO2/kWh
 *      Natural gas	various combined cycle turbines without scrubbing	~ 469 gCO2/kWh
 *      Coal	various generator types without scrubbing	~ 1001 gCO2/kWh
 * 
 * 
 * Logic used to control supply of tokens
 * --------------------------------------
 * 1. Carbon Intensity is reported every 30 minutes
 * 2. Delta is calculated by this smart contract
 * 3. If Delta = 0 ==> No change in carbon intensity ==> No change in supply
 * 4. If Delta > 0 ==> carbon intensity has gone WORSE ==> increase supply (to decrease price)
 * 5. If Delta < 0 ==> carbon intensity has gone BETTER ==> decrease supply (to increase price)
 * 
 * NB: 
 *  - increase/decrease supply = 50,000 tokens * delta gCO2/kWh
 *  - During night  ~ 190 gCO2/kWh
 *  - During day  ~ 275 gCO2/kWh
 * 
*/

pragma solidity >= 0.4.22 < 0.5;

import "./provableAPI.sol";

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

library DivOp {
    using SafeMath for uint256;
    
    function deltaOp(uint256 a, uint256 b) internal pure returns (uint256, bool) {
        if (a >= b) {
            return (a.sub(b), false);
        } else {
            return (b.sub(a), true);
        }
    }
}

library StringOp {
    
    function uintToString(uint v) internal pure returns (string str) {
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = byte(48 + remainder);
        }
        bytes memory s = new bytes(i + 1);
        for (uint j = 0; j <= i; j++) {
            s[j] = reversed[i - j];
        }
        str = string(s);
    }
    
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public central_bank;
    address public liquidity_bank;

    /**
      * @dev The Ownable constructor sets the original `owner` of the contract to the sender
      * account.
      */
    constructor() public {
        central_bank = 0xd8E5368a6c37069A4C9C2a23f46FF14D98eb051e;  // msg.sender;
        liquidity_bank = 0xb51C1888c35D3bEd065429bb46FaDdB666c446f7;
    }

    /**
      * @dev Throws if called by any account other than the owner.
      */
    modifier onlyCentralBank() {
        require(msg.sender == central_bank);
        _;
    }
    
    modifier onlyLiquidityBank() {
        require(msg.sender == liquidity_bank);
        _;
    }

    modifier onlyBank() {
        require(msg.sender == liquidity_bank || msg.sender == central_bank);
        _;
    }

    /**
    * @dev Allows the current owner to transfer control of the contract to a newOwner.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnershipCentralBank(address newOwner) public onlyCentralBank {
        if (newOwner != address(0)) {
            central_bank = newOwner;
        }
    }

    function transferOwnershipLiquidityBank(address newOwner) public onlyBank {
        if (newOwner != address(0)) {
            liquidity_bank = newOwner;
        }
    }

}

/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20Basic {
    uint public _totalSupply;
    function totalSupply() public constant returns (uint);
    function balanceOf(address who) public constant returns (uint);
    function transfer(address to, uint value) public;
    event Transfer(address indexed from, address indexed to, uint value);
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
    function allowance(address owner, address spender) public constant returns (uint);
    function transferFrom(address from, address to, uint value) public;
    function approve(address spender, uint value) public;
    event Approval(address indexed owner, address indexed spender, uint value);
}

/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances.
 */
contract BasicToken is Ownable, ERC20Basic {
    using SafeMath for uint;

    mapping(address => uint) public balances;

    // additional variables for use if transaction fees ever became necessary
    uint public basisPointsRate = 0;
    uint public maximumFee = 0;

    /**
    * @dev Fix for the ERC20 short address attack.
    */
    modifier onlyPayloadSize(uint size) {
        require(!(msg.data.length < size + 4));
        _;
    }

    /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    function transfer(address _to, uint _value) public onlyPayloadSize(2 * 32) {
        uint fee = (_value.mul(basisPointsRate)).div(10000);
        if (fee > maximumFee) {
            fee = maximumFee;
        }
        uint sendAmount = _value.sub(fee);
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(sendAmount);
        if (fee > 0) {
            balances[central_bank] = balances[central_bank].add(fee);
            emit Transfer(msg.sender, central_bank, fee);
        }
        emit Transfer(msg.sender, _to, sendAmount);
    }

    /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint representing the amount owned by the passed address.
    */
    function balanceOf(address _owner) public constant returns (uint balance) {
        return balances[_owner];
    }

}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based oncode by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is BasicToken, ERC20 {

    mapping (address => mapping (address => uint)) public allowed;

    uint public constant MAX_UINT = 2**256 - 1;

    /**
    * @dev Transfer tokens from one address to another
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint the amount of tokens to be transferred
    */
    function transferFrom(address _from, address _to, uint _value) public onlyPayloadSize(3 * 32) {
        uint256 _allowance = allowed[_from][msg.sender];

        // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
        // if (_value > _allowance) throw;

        uint fee = (_value.mul(basisPointsRate)).div(10000);
        if (fee > maximumFee) {
            fee = maximumFee;
        }
        if (_allowance < MAX_UINT) {
            allowed[_from][msg.sender] = _allowance.sub(_value);
        }
        uint sendAmount = _value.sub(fee);
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(sendAmount);
        if (fee > 0) {
            balances[central_bank] = balances[central_bank].add(fee);
            emit Transfer(_from, central_bank, fee);
        }
        emit Transfer(_from, _to, sendAmount);
    }

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    * @param _spender The address which will spend the funds.
    * @param _value The amount of tokens to be spent.
    */
    function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32) {

        // To change the approve amount you first have to reduce the addresses`
        //  allowance to zero by calling `approve(_spender, 0)` if it is not
        //  already 0 to mitigate the race condition described here:
        //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        require(!((_value != 0) && (allowed[msg.sender][_spender] != 0)));

        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
    }

    /**
    * @dev Function to check the amount of tokens than an owner allowed to a spender.
    * @param _owner address The address which owns the funds.
    * @param _spender address The address which will spend the funds.
    * @return A uint specifying the amount of tokens still available for the spender.
    */
    function allowance(address _owner, address _spender) public constant returns (uint remaining) {
        return allowed[_owner][_spender];
    }

}


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused = false;


  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   */
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   */
  modifier whenPaused() {
    require(paused);
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyCentralBank whenNotPaused public {
    paused = true;
    emit Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyCentralBank whenPaused public {
    paused = false;
    emit Unpause();
  }
}

contract BlackList is Ownable, BasicToken {

    /////// Getters to allow the same blacklist to be used also by other contracts (including upgraded Tether) ///////
    function getBlackListStatus(address _maker) external constant returns (bool) {
        return isBlackListed[_maker];
    }

    function getCentralBank() external constant returns (address) {
        return central_bank;
    }

    function getLiquidityBank() external constant returns (address) {
        return liquidity_bank;
    }

    mapping (address => bool) public isBlackListed;
    
    function addBlackList (address _evilUser) public onlyCentralBank {
        isBlackListed[_evilUser] = true;
        emit AddedBlackList(_evilUser);
    }

    function removeBlackList (address _clearedUser) public onlyCentralBank {
        isBlackListed[_clearedUser] = false;
        emit RemovedBlackList(_clearedUser);
    }

    function destroyBlackFunds (address _blackListedUser) public onlyCentralBank {
        require(isBlackListed[_blackListedUser]);
        uint dirtyFunds = balanceOf(_blackListedUser);
        balances[_blackListedUser] = 0;
        _totalSupply -= dirtyFunds;
        emit DestroyedBlackFunds(_blackListedUser, dirtyFunds);
    }

    event DestroyedBlackFunds(address _blackListedUser, uint _balance);

    event AddedBlackList(address _user);

    event RemovedBlackList(address _user);

}

contract UpgradedStandardToken is StandardToken{
    // those methods are called by the legacy contract
    // and they must ensure msg.sender to be the contract address
    function transferByLegacy(address from, address to, uint value) public;
    function transferFromByLegacy(address sender, address from, address spender, uint value) public;
    function approveByLegacy(address from, address spender, uint value) public;
}

contract UKCarbonIntensityToken is Pausable, StandardToken, BlackList, usingProvable {
    using DivOp for uint256;
    using StringOp for uint256;

    // Token attributes
    string public name;
    string public symbol;
    uint public decimals;
    address public upgradedAddress;
    bool public deprecated;
    uint public reserve;

    // UK Carbon Intensity attributes
    uint256 public intensity_actual;
    uint256 public intensity_actual_prev;

    // delta attributes
    bool public negative;
    uint256 public intensity_delta;
    
    // burn/min attributes
    uint256 public burnmint_factor;
    
    // init transfer variables
    bool public initialized_transfer;

    event AcquireCarbonIntensity();
    event CarbonIntensityAcquired(string intensity_val);
    event CallbackMYID(string myid);
    event NullIntensityMeasure();
    event IntensityDeltaCalculated();
    event IntensityInitialised();
    event NegativeIntensityDelta_BurningTokens(uint256 amount);
    event PositiveIntensityDelta_MintingTokens(uint256 amount);
    event DeltaNotZero();
    event InitializedTransferAlreadyDone();
    event InitializedTransfer();
    event LogError(string errorMsg);

    //  The contract can be initialized with a number of tokens
    //  All the tokens are deposited to the owner address
    //
    // @param _balance Initial supply of the contract
    // @param _name Token Name
    // @param _symbol Token symbol
    // @param _decimals Token decimals
    constructor() public {
        _totalSupply = 26000000000000000000000000;  // 26M total supply
        burnmint_factor = 20000000000000000000000;  // 20K burn/mint factor
        name = "UKCarbonIntensityToken";
        symbol = "UKCI";
        decimals = 18;
        reserve = 20;  // central bank reserve = 20%
        deprecated = false;
        initialized_transfer = false;
        
        // initial supply
        balances[central_bank] = _totalSupply;
        emit Transfer(address(0), central_bank, _totalSupply);
        
        // initial transfer of funds to liquidity_bank and first_trading_account
        initialize_transfers();
        
        // initialise carbon intensity data acquisition
        _update();
    }
    
    // transfer funds from central bank to _to
    function transfer_funds(address _to, uint amount) private {
        require(balances[central_bank] >= amount);
        balances[_to] += amount;
        balances[central_bank] -= amount;
        emit Transfer(central_bank, _to, amount);
    }
    
    // initial transfer of funds to liquidity_bank and first_trading_account
    function initialize_transfers() private {
        if (!initialized_transfer) {
            uint256 first_trading_amount = 2000000000000000000000000;  // first trading account to have 2M tokens
            uint fullpct = 100;
            address first_trading_account = 0x12839E12f6Ba954502826465e179B4e253df0d79;
            uint256 liquidity_supply = (_totalSupply.mul(fullpct.sub(reserve)).div(fullpct)).sub(first_trading_amount);
            transfer_funds(liquidity_bank, liquidity_supply);
            transfer_funds(first_trading_account, first_trading_amount);
            uint256 calc_total_supply = liquidity_supply.add(balances[central_bank]).add(first_trading_amount);
            
            if (_totalSupply != calc_total_supply) {
                emit LogError("initialize_transfers, cancelling: calculation error.");
                emit LogError(calc_total_supply.uintToString());
            } else {
                emit InitializedTransfer();
                initialized_transfer = true;
            }
        } else {
            emit InitializedTransferAlreadyDone();
        }
    }

    // Buy UKCI Tokens with ETH
    //
    // @param amount - eth amount to buy with
    function buy_token_in_eth_amount(uint256 amount) payable public whenNotPaused {
        require(msg.value == amount);
        uint256 token_amount = calculate_token_amount(amount);
        return transferFrom(liquidity_bank, msg.sender, token_amount);
    }
    
    function calculate_token_amount(uint256 amount) public view returns (uint256) {
        return balances[liquidity_bank].div(address(this).balance.div(amount));
    }

    /*function sell_token_in_eth_amount(uint256 amount) public {
        
    }

    function buy_token_in_ukci_amount(uint256 amount) public {
        
    }

    function sell_token_in_ukci_amount(uint256 amount) public {
        
    }*/

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transfer(address _to, uint _value) public whenNotPaused {
        _transfer(_to, _value);
    }
    
    function _transfer(address _to, uint _value) internal {
        require(!isBlackListed[msg.sender]);
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).transferByLegacy(msg.sender, _to, _value);
        } else {
            return super.transfer(_to, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transferFrom(address _from, address _to, uint _value) public whenNotPaused {
        require(!isBlackListed[_from]);
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).transferFromByLegacy(msg.sender, _from, _to, _value);
        } else {
            return super.transferFrom(_from, _to, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function balanceOf(address who) public constant returns (uint) {
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).balanceOf(who);
        } else {
            return super.balanceOf(who);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function approve(address _spender, uint _value) public onlyPayloadSize(2 * 32) {
        if (deprecated) {
            return UpgradedStandardToken(upgradedAddress).approveByLegacy(msg.sender, _spender, _value);
        } else {
            return super.approve(_spender, _value);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function allowance(address _owner, address _spender) public constant returns (uint remaining) {
        if (deprecated) {
            return StandardToken(upgradedAddress).allowance(_owner, _spender);
        } else {
            return super.allowance(_owner, _spender);
        }
    }

    // deprecate current contract in favour of a new one
    function deprecate(address _upgradedAddress) public onlyCentralBank {
        deprecated = true;
        upgradedAddress = _upgradedAddress;
        emit Deprecate(_upgradedAddress);
    }

    // deprecate current contract if favour of a new one
    function totalSupply() public constant returns (uint) {
        if (deprecated) {
            return StandardToken(upgradedAddress).totalSupply();
        } else {
            return _totalSupply;
        }
    }

    // Issue a new amount of tokens
    // these tokens are deposited into the owner address
    //
    // @param _amount Number of tokens to be issued
    function issue(uint amount) public onlyCentralBank {
        _issue(amount);
    }

    function _issue(uint amount) private {
        require(_totalSupply + amount > _totalSupply);
        require(balances[central_bank] + amount > balances[central_bank]);

        balances[central_bank] += amount;
        _totalSupply += amount;
        emit Issue(amount);
        emit Transfer(address(0), central_bank, amount);
    }
    
    function reset(uint amount) public onlyCentralBank {
        balances[central_bank] = amount;
        _totalSupply = amount;
        emit Reset(amount);
    }

    // Redeem tokens.
    // These tokens are withdrawn from the owner address
    // if the balance must be enough to cover the redeem
    // or the call will fail.
    // @param _amount Number of tokens to be issued
    function redeem(uint amount) public onlyCentralBank {
        _redeem(amount);
    }

    function _redeem(uint amount) private {
        require(_totalSupply >= amount);
        require(balances[central_bank] >= amount);

        _totalSupply -= amount;
        balances[central_bank] -= amount;
        emit Redeem(amount);
        emit Transfer(central_bank, address(0), amount);
    }

    function setParams(uint newBasisPoints, uint newMaxFee) public onlyCentralBank {
        // Ensure transparency by hardcoding limit beyond which fees can never be added
        require(newBasisPoints < 20);
        require(newMaxFee < 50);

        basisPointsRate = newBasisPoints;
        maximumFee = newMaxFee.mul(10**decimals);

        emit Params(basisPointsRate, maximumFee);
    }

    // Called when new token are issued
    event Issue(uint amount);

    // Called when tokens are redeemed
    event Redeem(uint amount);
    
    event Reset(uint amount);

    // Called when contract is deprecated
    event Deprecate(address newAddress);

    // Called if contract ever adds fees
    event Params(uint feeBasisPoints, uint maxFee);
    
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function parseInt(string _a, uint _b) internal pure returns (uint) {
      bytes memory bresult = bytes(_a);
      uint mint = 0;
      bool has_decimals = false;
      for (uint i = 0; i < bresult.length; i++) {
        if ((bresult[i] >= 48) && (bresult[i] <= 57)) {
          if (has_decimals) {
            if (_b == 0) break;
              else _b--;
          }
          mint *= 10;
          mint += uint(bresult[i]) - 48;
        } else if (bresult[i] == 46) has_decimals = true;
      }
      return mint;
    }

    /**
     * Acquire carbon intensity and calculate delta
     * 
     * */
    function __callback(
        bytes32 _myid,
        string memory _result
    )
        public 
    {
        require(msg.sender == provable_cbAddress());
        assert(_myid > 0);
        emit CarbonIntensityAcquired(_result);

        /* calculate intensity delta */
        
        // parse api response value to int
        uint256 current_intensity_actual = parseInt(_result, 0);
        
        if (current_intensity_actual == 0) {  // Null current intensity
        
            intensity_delta = 0;
            intensity_actual_prev = intensity_actual;
            emit NullIntensityMeasure();
            
        } else {  // Non-null current intensity
        
            if (intensity_actual_prev > 0) {  // previous intensity value exists
            
                (intensity_delta, negative) = current_intensity_actual.deltaOp(intensity_actual);
                intensity_actual_prev = intensity_actual;
                intensity_actual = current_intensity_actual;
                emit IntensityDeltaCalculated();
                
            } else {  // initialise intensity value
            
                intensity_actual = current_intensity_actual;
                intensity_actual_prev = current_intensity_actual;
                emit IntensityInitialised();
                
            }
            
        }
        
        // calculate burn/mint tokens based on delta value
        if (intensity_delta > 0) {
            
            emit DeltaNotZero();
            uint256 supply_demand_change = burnmint_factor.mul(intensity_delta);
            
            if (negative) {  // delta < 0 => burn supply
                
                emit NegativeIntensityDelta_BurningTokens(supply_demand_change);
                _redeem(supply_demand_change);
                
            } else {  // delta > 0 => mint supply
                
                emit PositiveIntensityDelta_MintingTokens(supply_demand_change);
                _issue(supply_demand_change);
                
            }
            
        }
    }

    function _update() private {
        emit AcquireCarbonIntensity();
        provable_query(
            "URL", 
            "json(https://api.carbonintensity.org.uk/intensity/date).data[0].intensity.actual"
        );
    }
    
    function update()
        public
        payable
    {
        _update();
    }
    
    function update_burnmint_factor(uint256 factor) 
        public onlyCentralBank
    {
        burnmint_factor = factor;
    }
    
    function withdraw_ETH(uint256 amount) public onlyCentralBank {
        require(address(this).balance >= amount);
        msg.sender.transfer(amount);
    }

    function deposit_ETH(uint256 amount) payable public {
        require(msg.value == amount);
        // nothing else to do!
    }

    function getBalance_ETH() public view returns (uint256) {
        return address(this).balance;
    }
    
    function get_price() public view returns (uint256) {
        uint256 eth_balance = address(this).balance;
        
        // if token supply > eth supply ==> price = token supply / eth supply, where 1 ETH = price in UKCI
        if (_totalSupply > eth_balance) {
            
            return _totalSupply.div(eth_balance);
            
        // if token supply < eth supply ==> price = eth supply / balance supply, where 1 UKCI = price in ETH
        } else if (_totalSupply < eth_balance) {
            
            return eth_balance.div(_totalSupply);
            
        // if token supply = eth supply ==> price = 1 (equal)
        } else {
            
            return 1;
            
        }
    }
    
    function get_price_type() public view returns (string memory) {
        uint256 eth_balance = address(this).balance;
        if (_totalSupply > eth_balance) {
            return "1 ETH WEI = get_price UKCI WEI";
        } else if (_totalSupply < eth_balance) {
            return "1 UKCI WEI = get_price ETH WEI";
        } else {
            return "1 UKCI = 1 ETH";
        }
    }
}