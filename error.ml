[@@@warning "-39"]

type api_error_item =
  { domain : string
  ; reason : string
  ; message : string
  ; location : string option [@default None]
  ; locationType : string option [@default None]
  } [@@deriving yojson]

type api_error =
  { errors : api_error_item list
  ; code: int
  ; message: string
  } [@@deriving yojson]

type api_error_response =
  { error : api_error
  } [@@deriving yojson]

[@@@warning "+39"]

type t =
  [ `Gcloud_auth_error of Auth.error
  | `Gcloud_api_error of Cohttp.Code.status_code * api_error_response option
  | `Json_parse_error of string
  | `Json_transform_error of string
  | `Network_error of exn
  ]

let pp fmt (error : t) =
  match error with
  | `Gcloud_auth_error error ->
    Format.fprintf fmt "Could not authenticate: %a" Auth.pp_error error
  | `Gcloud_api_error (status_code, api_error_response) ->
    Format.fprintf fmt "Gcloud API returned unexpected status code: %s (%s)"
      (Cohttp.Code.string_of_status status_code)
      (api_error_response
       |> CCOpt.map_or ~default:"Unable to decode error response body"
         (fun e -> Yojson.Safe.to_string (api_error_response_to_yojson e)))
  | `Json_parse_error msg ->
    Format.fprintf fmt "JSON parse error: %s" msg
  | `Json_transform_error msg ->
    Format.fprintf fmt "JSON transform error: %s" msg
  | `Network_error exn ->
    Format.fprintf fmt "Network error: %s" (Printexc.to_string exn)


let of_response_status_code_and_body (status_code : Cohttp.Code.status_code) (body : Cohttp_lwt.Body.t) : ('a, [> t]) Lwt_result.t =
  let open Lwt_result.Infix in
  Cohttp_lwt.Body.to_string body |> Lwt_result.ok >>= fun body_str ->
  let error_json =
    try
      Some (Yojson.Safe.from_string body_str)
    with
    | Yojson.Json_error _ -> None
  in
  let error =
    error_json
    |> CCOpt.flat_map
      (fun error_json ->
         error_json
         |> api_error_response_of_yojson
         |> CCResult.to_opt
      )
  in
  Lwt_result.fail (`Gcloud_api_error (status_code, error))