//! The deployed registry and Kyber MetaAggregationRouterV2 ABI. No generic
//! network-provided calldata passes through the signing boundary unchecked.
use crate::{address, bytes, number, Result};
use alloy_primitives::{Address, Bytes, B256, U256};
use alloy_sol_types::{sol, SolCall, SolValue};
use serde_json::{json, Value};

sol! {
    function commit(bytes32 commitment);
    function register(string name, string unifiedAddress, bytes32 secret);
    function refresh(uint256 positionId);
    function claimRewards(uint256 positionId);
    function release(uint256 positionId);
    function setUnifiedAddress(uint256 positionId, string unifiedAddress);
    function withdrawClaims();
    function approve(address spender, uint256 amount);
    function cbZEC() external view returns (address);
    function protocolId() external view returns (bytes32);
    function fixedDeposit() external view returns (uint256);
    function MIN_COMMITMENT_AGE() external view returns (uint256);
    function MAX_COMMITMENT_AGE() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function commitments(address owner, bytes32 commitment) external view returns (uint64);
    function claimableOf(address owner) external view returns (uint256 principal, uint256 rewardsScaled);
    function latestPositionOf(address owner) external view returns (uint256);
    function positionIdOf(string name) external view returns (uint256);
    function positionInfo(uint256 positionId) external view returns (address owner, string name, string unifiedAddress, uint64 registeredAt, uint64 maturityAt, uint64 refreshDueAt, uint64 graceEndsAt, bool participating, bool retired, uint256 rewardCreditScaled);
    function exitPreview(uint256 positionId) external view returns (bool early, uint256 principalReturned, uint256 rewardsReturned, uint256 principalForfeited, uint256 rewardsForfeitedScaled);
    function available(string name) external view returns (bool);
    function resolve(string name) external view returns (string);
    function recordOf(string name) external view returns (address registrant, string unifiedAddress, uint64 expiry, bool active);
    struct Execution { address target; uint256 value; bytes data; }
    function execute(Execution[] calls, uint256 deadline);
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address[] srcReceivers;
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }
    struct SwapExecutionParams {
        address callTarget;
        address approveTarget;
        bytes targetData;
        SwapDescription desc;
        bytes clientData;
    }
    function swap(SwapExecutionParams execution) external payable returns (uint256 returnAmount, uint256 gasUsed);
}

pub fn commitment(
    registry: Address,
    chain: u64,
    name: &str,
    ua: &str,
    owner: Address,
    secret: B256,
) -> B256 {
    let type_hash = alloy_primitives::keccak256("ZNS commitment(bytes32 protocolId,address registry,uint256 chainId,string name,string unifiedAddress,address registrant,bytes32 secret)");
    alloy_primitives::keccak256(
        (
            type_hash,
            crate::PROTOCOL_ID
                .parse::<B256>()
                .expect("fixed protocol identifier"),
            registry,
            U256::from(chain),
            name.to_owned(),
            ua.to_owned(),
            owner,
            secret,
        )
            .abi_encode_params(),
    )
}

pub fn read_call(method: &str, args: &Value) -> Result<String> {
    let field = |key: &str| {
        args.get(key)
            .and_then(Value::as_str)
            .ok_or_else(|| format!("Missing {key}"))
    };
    let name = || -> Result<String> {
        let name = field("name")?;
        crate::validate_name(name)?;
        Ok(name.into())
    };
    let data = match method {
        "cbZEC" => cbZECCall {}.abi_encode(),
        "protocolId" => protocolIdCall {}.abi_encode(),
        "fixedDeposit" => fixedDepositCall {}.abi_encode(),
        "MIN_COMMITMENT_AGE" => MIN_COMMITMENT_AGECall {}.abi_encode(),
        "MAX_COMMITMENT_AGE" => MAX_COMMITMENT_AGECall {}.abi_encode(),
        "decimals" => decimalsCall {}.abi_encode(),
        "balanceOf" => balanceOfCall {
            account: address(field("owner")?)?,
        }
        .abi_encode(),
        "allowance" => allowanceCall {
            owner: address(field("owner")?)?,
            spender: address(field("spender")?)?,
        }
        .abi_encode(),
        "commitments" => commitmentsCall {
            owner: address(field("owner")?)?,
            commitment: field("commitment")?
                .parse()
                .map_err(|_| "Invalid commitment")?,
        }
        .abi_encode(),
        "claimableOf" => claimableOfCall {
            owner: address(field("owner")?)?,
        }
        .abi_encode(),
        "latestPositionOf" => latestPositionOfCall {
            owner: address(field("owner")?)?,
        }
        .abi_encode(),
        "positionIdOf" => positionIdOfCall { name: name()? }.abi_encode(),
        "positionInfo" => positionInfoCall {
            positionId: number(field("positionId")?)?,
        }
        .abi_encode(),
        "exitPreview" => exitPreviewCall {
            positionId: number(field("positionId")?)?,
        }
        .abi_encode(),
        "available" => availableCall { name: name()? }.abi_encode(),
        "resolve" => resolveCall { name: name()? }.abi_encode(),
        "recordOf" => recordOfCall { name: name()? }.abi_encode(),
        _ => return Err("Unsupported ZNS read method".into()),
    };
    Ok(format!("0x{}", hex::encode(data)))
}

pub fn decode_result(method: &str, data: &str) -> Result<Value> {
    let data = bytes(data)?;
    let err = |_| "Invalid ABI response".to_string();
    Ok(match method {
        "cbZEC" => json!(Address::abi_decode(&data, true)
            .map_err(err)?
            .to_checksum(None)),
        "protocolId" => json!(B256::abi_decode(&data, true).map_err(err)?.to_string()),
        "fixedDeposit" | "MIN_COMMITMENT_AGE" | "MAX_COMMITMENT_AGE" | "balanceOf"
        | "allowance" | "latestPositionOf" | "positionIdOf" => {
            json!(U256::abi_decode(&data, true).map_err(err)?.to_string())
        }
        "decimals" => json!(
            decimalsCall::abi_decode_returns(&data, true)
                .map_err(err)?
                ._0
        ),
        "commitments" => json!(u64::abi_decode(&data, true).map_err(err)?.to_string()),
        "resolve" => json!(String::abi_decode(&data, true).map_err(err)?),
        "available" => json!(bool::abi_decode(&data, true).map_err(err)?),
        "claimableOf" => {
            let v = claimableOfCall::abi_decode_returns(&data, true).map_err(err)?;
            json!({"principal":v.principal.to_string(),"rewardsScaled":v.rewardsScaled.to_string()})
        }
        "positionInfo" => {
            let v = positionInfoCall::abi_decode_returns(&data, true).map_err(err)?;
            json!({"owner":v.owner.to_checksum(None),"name":v.name,"unifiedAddress":v.unifiedAddress,
              "registeredAt":v.registeredAt.to_string(),"maturityAt":v.maturityAt.to_string(),
              "refreshDueAt":v.refreshDueAt.to_string(),"graceEndsAt":v.graceEndsAt.to_string(),
              "participating":v.participating,"retired":v.retired,"rewardCreditScaled":v.rewardCreditScaled.to_string()})
        }
        "exitPreview" => {
            let v = exitPreviewCall::abi_decode_returns(&data, true).map_err(err)?;
            json!({"early":v.early,"principalReturned":v.principalReturned.to_string(),"rewardsReturned":v.rewardsReturned.to_string(),
              "principalForfeited":v.principalForfeited.to_string(),"rewardsForfeitedScaled":v.rewardsForfeitedScaled.to_string()})
        }
        "recordOf" => {
            let v = recordOfCall::abi_decode_returns(&data, true).map_err(err)?;
            json!({"registrant": v.registrant.to_checksum(None), "unifiedAddress": v.unifiedAddress, "expiry": v.expiry.to_string(), "active": v.active})
        }
        _ => return Err("Unsupported ZNS read method".into()),
    })
}

pub fn validate_swap(
    data: &str,
    value: &str,
    minimum_output: &str,
    owner: Address,
    token: Address,
    max_value: U256,
) -> Result<Bytes> {
    let data = bytes(data)?;
    if data.len() > 64 * 1024 {
        return Err("Swap calldata is too large".into());
    }
    let call = swapCall::abi_decode(&data, true)
        .map_err(|_| "Unsupported or malformed Kyber swap calldata")?;
    // Canonical re-encoding rejects appended junk and noncanonical offsets.
    if call.abi_encode() != data {
        return Err("Noncanonical swap calldata".into());
    }
    let desc = &call.execution.desc;
    let amount = number(value)?;
    let min = number(minimum_output)?;
    let native = address("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE")?;
    if desc.srcToken != native || desc.dstToken != token || desc.dstReceiver != owner {
        return Err("Swap must exchange native ETH for this account's cbZEC".into());
    }
    if amount.is_zero()
        || amount > max_value
        || desc.amount != amount
        || min.is_zero()
        || desc.minReturnAmount < min
    {
        return Err("Swap amount or minimum output exceeds the reviewed intent".into());
    }
    // 0x200 is currently ignored by the verified MetaAggregationRouterV2
    // implementation. Fee, partial-fill, claim and alternate execution flags
    // are deliberately rejected. Revisit on any router version change.
    if ![U256::ZERO, U256::from(512)].contains(&desc.flags)
        || !desc.permit.is_empty()
        || !desc.feeReceivers.is_empty()
        || !desc.feeAmounts.is_empty()
        || !desc.srcReceivers.is_empty()
        || !desc.srcAmounts.is_empty()
    {
        return Err("Unsupported swap flags, fees, source distribution, or permit".into());
    }
    if call.execution.approveTarget != Address::ZERO || call.execution.callTarget == Address::ZERO {
        return Err("Native swap must not request token approval".into());
    }
    Ok(data.into())
}
