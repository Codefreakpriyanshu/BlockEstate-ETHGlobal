//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./propertyRegistry.sol";
import { ISP } from "@ethsign/sign-protocol-evm/src/interfaces/ISP.sol";
import { Ownable } from "openzeppelin/contracts/access/Ownable"; 
import { Attestation } from "@ethsign/sign-protocol-evm/src/models/Attestation.sol";

contract RentToOwn is PropertyRegistry, Ownable{



    ISP public spInstance;
    uint64 public schemaId;
    mapping(address tenant=>address landlord) public tenantLandlordAgreement;

    error ConfirmationAddressMismatch();

    constructor() Ownable(msg.sender){ }




    uint256 public SECONDS_IN_MONTH = 2629056;
    uint256 public cancellationPenalty = 5; // cancellation penalty in percentage

    mapping(uint256=>address) public tenant;
    mapping(uint256=>uint256) public numberOfYears;
    mapping(uint256=>uint256) public monthlyemi;
    mapping(uint256=>uint256) public totalPaid;
    mapping(uint256=>uint256) public numberOfPayments;
    mapping(uint256=>uint256) public lastPayment;

      event PaymentMade(
        address from,
        uint amount
    );

    function RentProperty(uint256 property_index, uint256 numberofyears) external{
        require(properties[property_index].owned == false, "Property is already occupied");
        require(numberOfYears[property_index]<=8, "Number of years can't be more than 8");
                numberOfYears[property_index]=numberofyears;

        tenantLandlordAgreement[msg.sender]=properties[property_index].owner;

       

    }

    function ApproveTenant(uint256 property_index, address _tenant) external returns (uint64){
        bytes[] memory recipients = new bytes[](2);
        recipients[0]= abi.encode(_tenant);
        recipients[1]= abi.encode(msg.sender);
        
        if(tenantLandlordAgreement[_tenant]== msg.sender){

        tenant[property_index]=_tenant;
        properties[property_index].owned == true;
        numberOfPayments[property_index]=0;
        if(numberofyears<=3){
            monthlyemi[property_index]=(110*properties[property_index].price)/(100*numberOfYears[property_index]*12);
        }
        else if(numberofyears>3 && numberofyears<6 ){
            monthlyemi[property_index]=(115*properties[property_index].price)/(100*numberOfYears[property_index]*12);

        }
        else{
            monthlyemi[property_index]=(120*properties[property_index].price)/(100*numberOfYears[property_index]*12);

        }

        Attestation memory a = Attestation({
            schemaId: schemaId,
            linkedAttestationId: 0,
            attestTimestamp: 0,
            revokeTimestamp: 0,
            attester: address(this),
            validUntil: 0,
            dataLocation: 0,
            revoked: false,
            recipients: recipients,
            data: ""

        });

        return spInstance.attest(a,"","","");




        }
        else{
            revert ConfirmationAddressMismatch();
        }

    }


    function payRent(uint256 property_index) public payable {
        require(
            msg.sender == tenant[property_index],
            "Only the tenant can make payments."
        );
        require(
            msg.value >= properties[property_index].rent + monthlyemi[property_index],
            "Must pay at least the rent amount."
        );
        require(
            properties[property_index].owned == true,
            "No tenant currently"
        );
        
        uint excessAmount = msg.value - properties[property_index].rent - monthlyemi[property_index];
        if (excessAmount > 0) {
            // Refund excess payment
            payable(msg.sender).transfer(excessAmount);
        }
        
        totalPaid[property_index] += monthlyemi[property_index];
        numberOfPayments[property_index] += 1;

        payable(properties[property_index].owner).transfer(properties[property_index].rent + monthlyemi[property_index]);
        
        lastPayment[property_index] = block.timestamp;
        
        emit PaymentMade(msg.sender, properties[property_index].rent + monthlyemi[property_index]);
    }

    function adjustRent(uint256 _newRentAmount, uint256 property_index ) public {
        // Checks that the sender is the landlord
        require(
            msg.sender == properties[property_index].owner,
            "Only the landlord can adjust the rent."
        );
        // Checks that the new rent isn't more than 10% higher than the old rent
        require(
            _newRentAmount <= properties[property_index].rent * 110 / 100,
            "Cannot increase rent by more than 10%."
        );
        
        properties[property_index].rent = _newRentAmount;
    }

    function cancelAgreement(uint256 property_index) public {
        // Checks that the sender is the tenant
        require(
            msg.sender == tenant[property_index],
            "Only the tenant can cancel the agreement."
        );
        
        // Calculates the refund amount (total paid minus the cancellation penalty)
        uint refundAmount = totalPaid[property_index] * (100 - cancellationPenalty) / 100;
        
        // Return the refund amount to the tenant
        payable(tenant[property_index]).transfer(refundAmount);
        
        // Reset the state of the contract
        totalPaid[property_index] = 0;
        numberOfPayments[property_index] = 0;
        properties[property_index].owned= false;
    }

 
    function checkPaymentDue(uint256 property_index) public view returns (bool) {
        return block.timestamp > lastPayment[property_index] + SECONDS_IN_MONTH ;
    }


    function landlordCancelAgreement(uint256 property_index) public {
        // Checks that the sender is the landlord
        require(
            msg.sender == properties[property_index].owner,
            "Only the landlord can cancel the agreement."
        );
        // Checks that a payment is due
        require(
            checkPaymentDue(property_index),
            "Cannot cancel if payment is not due."
        );

        // The tenant forfeits a percentage of what they've paid
        uint refundAmount = totalPaid[property_index] * (100 - cancellationPenalty) / 100;

        // Return the refund amount to the tenant
    payable(tenant[property_index]).transfer(refundAmount);

        // Reset the state of the contract
        totalPaid[property_index] = 0;
        numberOfPayments[property_index] = 0;
        properties[property_index].owned = false;
    }



    function setSPInstance(address instance) external onlyOwner{
        spInstance=ISP(instance);
    }


    function setSchemaId(uint64 _schemId) external onlyOwner{
        schemaId=_schemId;
    }
    


    
}