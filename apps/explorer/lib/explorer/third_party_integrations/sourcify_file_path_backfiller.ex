defmodule Explorer.ThirdPartyIntegrations.SourcifyFilePathBackfiller do
  alias BlockScoutWeb.AddressContractVerificationController, as: VerificationController
  alias Ecto.Changeset
  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.{SmartContract, SmartContractAdditionalSource}
  alias Explorer.Chain.Hash.Address

  alias Explorer.ThirdPartyIntegrations.Sourcify

  import Ecto.Query,
    only: [
      from: 2,
      preload: 2
    ]

  require Logger

  def perform() do
    fetch_all_unfilled_contracts()
    |> Enum.each(fn contract ->
      with {:address_hash, address_hash_string} <-
             {:address_hash, "0x" <> Base.encode16(contract.address_hash.bytes, case: :lower)},
           {:ok, _full_or_partial, metadata} <- Sourcify.check_by_address_any(address_hash_string),
           %{
             "params_to_publish" => _params_to_publish,
             "abi" => _abi,
             "secondary_sources" => secondary_sources,
             "compilation_target_file_path" => compilation_target_file_path
           } <- VerificationController.parse_params_from_sourcify(address_hash_string, metadata) do
        sc_additional_sources_query =
          from(as in SmartContractAdditionalSource,
            where: as.address_hash == ^contract.address_hash
          )

        sc_additional_sources_query
        |> Repo.all()
        |> Enum.each(fn source ->
          new_name =
            if !is_nil(res = Enum.find(secondary_sources, fn src -> src["file_name"] =~ source.file_name end)),
              do: res["file_name"],
              else: nil

          if !is_nil(new_name) do
            source
            |> Changeset.change(%{file_name: new_name})
            |> Repo.update()
          end
        end)

        contract
        |> Changeset.change(%{file_path: compilation_target_file_path})
        |> Repo.update()
      else
        _error ->
          Logger.debug([
            "Coudn't fetch file paths for #{"0x" <> Base.encode16(contract.address_hash.bytes, case: :lower)} from Sourcify"
          ])
      end
    end)
  end

  def fetch_all_unfilled_contracts() do
    query =
      from(sc in SmartContract,
        where: sc.verified_via_sourcify == true and is_nil(sc.file_path)
      )

    query
    |> Repo.all()
  end
end
