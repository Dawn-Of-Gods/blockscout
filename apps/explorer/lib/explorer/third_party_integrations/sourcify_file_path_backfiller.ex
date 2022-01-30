defmodule Explorer.ThirdPartyIntegrations.SourcifyFilePathBackfiller do
  alias BlockScoutWeb.AddressContractVerificationController, as: VerificationController
  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.SmartContract
  alias Explorer.Chain.Hash.Address
  
  alias Explorer.ThirdPartyIntegrations.Sourcify

  import Ecto.Query,
    only: [
      from: 2
    }

  def perform() do
    fetch_all_unfilled_contracts()
    |> Enum.each(fn contract -> 
      with {:address_hash, {:ok, address_hash_string}} <- {:address_hash, Address.dump(contract.address_hash)},
      {:ok, _full_or_partial, metadata} <- Sourcify.check_by_address_any(address_hash_string),
      %{
        "params_to_publish" => _params_to_publish,
        "abi" => _abi,
        "secondary_sources" => secondary_sources,
        "compilation_target_file_path" => compilation_target_file_path
      } <- VerificationController.parse_params_from_sourcify(address_hash_string, metadata) do
        
      end
    end)
  end

  def fetch_all_unfilled_contracts() do
    query =
      from(sc in SmartContract, 
        where: sc.verified_via_sourcify == true and is_nil(sc.file_path)
      )

    query
    |> join_associations(%{smart_contract_additional_sources: :optional})
    |> Repo.all()
  end
end