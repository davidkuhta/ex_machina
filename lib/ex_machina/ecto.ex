defmodule ExMachina.Ecto do
  @moduledoc """
  Module for building and inserting factories with Ecto

  This module works much like the regular `ExMachina` module, but adds a few
  nice things that make working with Ecto easier.

  * It uses `ExMachina.EctoStrategy`, which adds `insert/1`, `insert/2`,
    `insert_pair/2`, `insert_list/3`.
  * Adds a `params_for` function that is useful for working with changesets or
    sending params to API endpoints.

  More in-depth examples are in the [README](README.html).
  """
  defmacro __using__(opts) do
    verify_ecto_dep
    if repo = Keyword.get(opts, :repo) do
      quote do
        use ExMachina
        use ExMachina.EctoStrategy, repo: unquote(repo)

        def params_for(factory_name, attrs \\ %{}) do
          ExMachina.Ecto.params_for(__MODULE__, factory_name, attrs)
        end

        def params_with_assocs(factory_name, attrs \\ %{}) do
          ExMachina.Ecto.params_with_assocs(__MODULE__, factory_name, attrs)
        end

        def fields_for(factory_name, attrs \\ %{}) do
          raise "fields_for/2 has been renamed to params_for/2."
        end
      end
    else
      raise ArgumentError,
        """
        expected :repo to be given as an option. Example:

        use ExMachina.Ecto, repo: MyApp.Repo
        """
    end
  end

  defp verify_ecto_dep do
    unless Code.ensure_loaded?(Ecto) do
      raise "You tried to use ExMachina.Ecto, but the Ecto module is not loaded. " <>
        "Please add ecto to your dependencies."
    end
  end

  @doc """
  Builds a factory with the passed in factory_name and returns its fields

  This is only for use with Ecto models.

  Will return a map with the fields and virtual fields, but without the Ecto
  metadata, associations, and the primary key.

  If you want belongs_to associations to be inserted, use
  `params_with_assocs/2`.

  ## Example

      def user_factory do
        %MyApp.User{name: "John Doe", admin: false}
      end

      # Returns %{name: "John Doe", admin: true}
      params_for(:user, admin: true)
  """
  def params_for(module, factory_name, attrs \\ %{}) do
    module.build(factory_name, attrs)
    |> drop_ecto_fields
  end

  @doc """
  Same as `params_for/2`, but inserts all belongs_to associations and sets the
  foreign keys.

  ## Example

      def article_factory do
        %MyApp.Article{title: "An Awesome Article", author: build(:author)}
      end

      # Inserts an author and returns %{title: "An Awesome Article", author_id: 12}
      params_with_assocs(:article)
  """
  def params_with_assocs(module, factory_name, attrs \\ %{}) do
    module.build(factory_name, attrs)
    |> insert_belongs_to_assocs(module)
    |> drop_ecto_fields
  end

  defp insert_belongs_to_assocs(record = %{__struct__: struct, __meta__: %{__struct__: Ecto.Schema.Metadata}}, module) do
    Enum.reduce(struct.__schema__(:associations), record, fn(association_name, record) ->
      case struct.__schema__(:association, association_name) do
        association = %{__struct__: Ecto.Association.BelongsTo} ->
          insert_built_belongs_to_assoc(
            module,
            association.owner_key,
            association_name,
            record
          )
        _ -> record
      end
    end)
  end

  def insert_built_belongs_to_assoc(module, foreign_key, association_name, record) do
    case Map.get(record, association_name) do
      built_relation = %{__meta__: %{state: :built}} ->
        relation = built_relation |> module.insert
        Map.put(record, foreign_key, relation.id)
      _ -> Map.delete(record, foreign_key)
    end
  end

  defp drop_ecto_fields(record = %{__struct__: struct, __meta__: %{__struct__: Ecto.Schema.Metadata}}) do
    record
    |> Map.from_struct
    |> Map.delete(:__meta__)
    |> Map.drop(struct.__schema__(:associations))
    |> Map.drop(struct.__schema__(:primary_key))
  end
  defp drop_ecto_fields(record) do
    raise ArgumentError, "#{inspect record} is not an Ecto model. Use `build` instead."
  end
end
