defmodule Kazan.Client do
  @moduledoc """
  Kazan.Client sends requests to a kubernetes server.

  These requests should be built using the functions in the `Kazan.Apis` module.
  """
  alias Kazan.{Request, Server}

  @type run_result :: {:ok, struct} | {:error, term}

  @doc """
  Makes a request against a kube server.

  The server should be set in the kazan config or provided in the options.

  ### Options

  * `server` - A `Kazan.Server` struct that defines which server we should send
    this request to. This will override any server provided in the Application
    config.
  * `stream_to` - A `pid` to which responses are sent.  This will create a Async
     request with HTTPoison.
  """
  @spec run(Request.t, Keyword.t) :: run_result
  def run(request, options \\ []) do
    server = find_server(options)

    headers = [{"Accept", "application/json"}]
    headers = headers ++ case request.content_type do
                           nil -> []
                           type -> [{"Content-Type", type}]
                         end

    headers = headers ++ case server.auth do
      %Server.TokenAuth{token: token} -> [{"Authorization", "Bearer #{token}"}]
      _ -> []
    end

    stream_to = Keyword.get(options, :stream_to)

    request_options =
      [ params: request.query_params,
        ssl: ssl_options(server)]

    request_options =
      case stream_to do
        nil ->
          request_options
        pid ->
          request_options ++
          [ stream_to: pid,
            recv_timeout: 60 * 60 * 1000 ]
      end

    res = HTTPoison.request(
      method(request.method),
      server.url <> request.path,
      request.body || "",
      headers,
      request_options
    )

    case stream_to do
      nil ->
        with {:ok, result} <- res,
             {:ok, body} <- check_status(result),
             {:ok, data} <- Poison.decode(body),
             {:ok, model} <- Kazan.Models.decode(data, request.response_schema),
             do: {:ok, model}
      _pid ->
        case res do
          {:ok, %HTTPoison.AsyncResponse{id: id}} -> {:ok, id}
          other -> other
        end
    end
  end

  @doc """
  Like `run/2`, but raises on Error.  See `run/2` for more details.
  """
  @spec run!(Request.t, Keyword.t) :: struct | no_return
  def run!(request, options \\ []) do
    case run(request, options) do
      {:ok, result} -> result
      {:error, reason} -> raise Kazan.RemoteError, reason: reason
    end
  end

  # Figures out which server we should use.  In order of preference:
  # - A server specified in the keyword arguments
  # - A server specified in the kazan config
  @spec find_server(Keyword.t) :: Server.t
  defp find_server(options) do
    case Keyword.get(options, :server) do
      nil ->
        case Application.get_env(:kazan, :server) do
          nil -> raise "No server is configured"
          details -> struct(Server, details)
        end
      server -> server
    end
  end

  defp method("get"), do: :get
  defp method("post"), do: :post
  defp method("put"), do: :put
  defp method("delete"), do: :delete
  defp method("patch"), do: :patch

  @spec check_status(HTTPoison.Response.t) :: {:ok, String.t}
  defp check_status(%{status_code: code, body: body}) when code in 200..299 do
    {:ok, body}
  end
  defp check_status(%{status_code: other, body: body}) do
    data =
      case Poison.decode(body) do
        {:ok, data} -> data
        _ -> body
      end
    {:error, {:http_error, other, data}}
  end

  @spec ssl_options(Server.t) :: Keyword.t
  defp ssl_options(server) do
    auth_options = ssl_auth_options(server.auth)
    verify_options = case server.insecure_skip_tls_verify do
      true -> [verify: :verify_none]
      _ -> []
    end
    ca_options = case server.ca_cert do
      nil -> []
      cert -> [cacerts: [cert]]
    end
    auth_options ++ verify_options ++ ca_options
  end

  defp ssl_auth_options(%Server.CertificateAuth{certificate: cert, key: key}) do
    [cert: cert, key: key]
  end
  defp ssl_auth_options(_), do: []
end
