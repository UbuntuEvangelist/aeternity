%%%-------------------------------------------------------------------
%%% @copyright (C) 2018, Aeternity Anstalt
%%% @doc
%%%    Naming System API
%%% @end
%%%-------------------------------------------------------------------

-module(aens).

%% API
-export([resolve/3,
         resolve_hash/3,
         resolve_from_name_object/2,
         get_commitment_hash/2,
         get_name_entry/2,
         get_name_hash/1]).

%%%===================================================================
%%% Types
%%%===================================================================

%%%===================================================================
%%% API
%%%===================================================================

-spec resolve(binary(), binary(), aens_state_tree:tree()) ->
    {ok, aeser_id:id()} | {error, atom()}.
resolve(Key, Name, NSTree) when is_binary(Key), is_binary(Name) ->
    case is_name(Name) of
        true ->
            case name_to_name_hash(Name) of
                {ok, NameHash} ->
                    resolve_hash(Key, NameHash, NSTree);
                {error, _Rsn} = Error ->
                    Error
            end;
        false ->
            AllowedTypes = [account_pubkey, oracle_pubkey, contract_pubkey, channel],
            aeser_api_encoder:safe_decode({id_hash, AllowedTypes}, Name)
    end.

-spec resolve_hash(binary(), binary(), aens_state_tree:tree()) ->
    {ok, aens_pointer:id_type()} | {error, atom()}.
resolve_hash(Key, NameHash, NSTree) when is_binary(Key), is_binary(NameHash) ->
    case name_hash_to_name_entry(NameHash, NSTree) of
        {ok, #{pointers := Pointers}} -> find_pointer_id(Key, Pointers);
        {error, _Rsn} = Error -> Error
    end.

-spec resolve_from_name_object(binary(), aens_names:name()) ->
    {ok, aens_pointer:id_type()} | {error, atom()}.
resolve_from_name_object(Key, Name) when is_binary(Key) ->
    case name_entry(Name) of
        {ok, #{pointers := Pointers}} -> find_pointer_id(Key, Pointers);
        {error, _Rsn} = Error -> Error
    end.

-spec get_commitment_hash(binary(), integer()) ->
    {ok, aens_hash:commitment_hash()} | {error, atom()}.
get_commitment_hash(Name, Salt) when is_binary(Name) andalso is_integer(Salt) ->
    case aens_utils:to_ascii(Name) of
        {ok, NameAscii} ->
          try {ok, aens_hash:commitment_hash(NameAscii, Salt)}
          catch _:R -> {error, R} end;
        {error, _} = E  -> E
    end.

-spec get_name_entry(binary(), aens_state_tree:tree()) ->
    {ok, map()} | {error, atom()}.
get_name_entry(Name, NSTree) when is_binary(Name) ->
    case name_to_name_hash(Name) of
        {ok, NameHash} -> name_hash_to_name_entry(NameHash, NSTree);
        {error, _} = Error -> Error
    end.

-spec get_name_hash(binary()) ->
    {ok, aens_hash:name_hash()} | {error, atom()}.
get_name_hash(Name) when is_binary(Name) ->
    name_to_name_hash(Name).

%%%===================================================================
%%% Internal functions
%%%===================================================================

is_name(Bin) ->
    length(aens_utils:name_parts(Bin)) > 1.

-spec name_to_name_hash(binary()) -> {ok, binary()} | {error, atom()}.
name_to_name_hash(Name) ->
    case aens_utils:to_ascii(Name) of
        {ok, NameAscii} ->
            NameHash = aens_hash:name_hash(NameAscii),
            {ok, NameHash};
        {error, {bad_label, _}} -> {error, invalid_name};
        {error, {invalid_codepoint, _}} -> {error, invalid_name};
        {error, _Rsn} = Error ->
            Error
    end.

name_hash_to_name_entry(NameHash, NSTree) ->
    case aens_state_tree:lookup_name(NameHash, NSTree) of
        {value, NameRecord} -> name_entry(NameRecord);
        none -> {error, name_not_found}
    end.

name_entry(NameRecord) ->
    case aens_names:status(NameRecord) of
        claimed ->
            {ok, #{id       => aens_names:id(NameRecord),
                   ttl      => aens_names:ttl(NameRecord),
                   owner    => aens_names:owner_pubkey(NameRecord),
                   pointers => aens_names:pointers(NameRecord)}};
        revoked ->
            {error, name_revoked}
    end.

find_pointer_id(Key, [Pointer | Rest]) ->
    case Key =:= aens_pointer:key(Pointer) of
        true -> {ok, aens_pointer:id(Pointer)};
        false -> find_pointer_id(Key, Rest)
    end;
find_pointer_id(_Key, []) ->
    {error, pointer_id_not_found}.
