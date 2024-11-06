// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.15;

contract AddressSet {
    error IndexInvalid(uint256 index);
    error DuplicateAddress(address _address);

    event AddressAdded(address element);
    event AddressRemoved(address element);

    uint256 private _elementCount;

    mapping(uint256 => address) private _elementMap;

    mapping(address => uint256) private _elementPresent;

    constructor() {
        _elementCount = 0;
    }

    modifier requireValidIndex(uint256 index) {
        if (index == 0 || index > _elementCount) revert IndexInvalid(index);
        _;
    }

    function add(address _element) external returns (uint256) {
        uint256 elementIndex = ++_elementCount;
        _elementMap[elementIndex] = _element;
        if (_elementPresent[_element] > 0) revert DuplicateAddress(_element);
        _elementPresent[_element] = elementIndex;
        emit AddressAdded(_element);
        return elementIndex;
    }

    function erase(uint256 _index) external returns (bool) {
        address _element = _elementMap[_index];
        return erase(_element);
    }

    function erase(address _element) public returns (bool) {
        uint256 elementIndex = _elementPresent[_element];
        if (elementIndex > 0) {
            address _lastElement = _elementMap[_elementCount];
            _elementMap[elementIndex] = _lastElement;
            _elementPresent[_lastElement] = elementIndex;
            _elementMap[_elementCount] = address(0x0);
            _elementPresent[_element] = 0;
            delete _elementMap[_elementCount];
            delete _elementPresent[_element];
            _elementCount--;
            emit AddressRemoved(_element);
            return true;
        }
        return false;
    }

    function size() external view returns (uint256) {
        return _elementCount;
    }

    function get(uint256 index) external view requireValidIndex(index) returns (address) {
        return _elementMap[index];
    }

    function contains(address _element) external view returns (bool) {
        return find(_element) > 0;
    }

    function find(address _element) public view returns (uint256) {
        return _elementPresent[_element];
    }
}