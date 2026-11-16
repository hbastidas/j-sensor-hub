NB. ===========================================================================
NB. J Sensor Hub - Servidor Web HTTP Nativo en J (J9.7) para Google Pixel
NB. Compatible con Android 16 Linux Terminal (linux_vm_manager port forwarding)
NB. https://www.jsoftware.com/
NB. ===========================================================================

require 'socket'
0!:0 < '/home/droid/j-sensor-hub/sensors.ijs'

cocurrent 'base'

PORT_HUB   =: 8000
PUBLIC_DIR =: '/home/droid/j-sensor-hub/public'

FAVICON_SVG =: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="#1d4ed8"/><text x="32" y="46" font-family="monospace" font-size="42" font-weight="bold" fill="#33d2f6" text-anchor="middle">J</text></svg>'

http_response =: 4 : 0
  'status ctype' =. x
  body =. , y
  hdr =. 'HTTP/1.1 ' , status , CRLF
  hdr =. hdr , 'Content-Type: ' , ctype , CRLF
  hdr =. hdr , 'Content-Length: ' , (": # body) , CRLF
  hdr =. hdr , 'Access-Control-Allow-Origin: *' , CRLF
  hdr =. hdr , 'Access-Control-Allow-Methods: GET, POST, OPTIONS' , CRLF
  hdr =. hdr , 'Access-Control-Allow-Headers: Content-Type' , CRLF
  hdr =. hdr , 'Cache-Control: no-cache, no-store, must-revalidate' , CRLF
  hdr =. hdr , 'Connection: close' , CRLF , CRLF
  hdr , body
)

serve_static =: 4 : 0
  ctype =. x
  fpath =. PUBLIC_DIR , y
  try.
    content =. 1!:1 < fpath
    ('200 OK' ; ctype) http_response content
  catch.
    ('404 Not Found' ; 'text/plain; charset=utf-8') http_response 'Archivo no encontrado: ' , y
  end.
)

get_content_length =: 3 : 0
  hdr =. tolower y
  pos =. ('content-length:' E. hdr) i. 1
  if. pos < # hdr do.
    rest =. (pos + 15) }. hdr
    line =. (rest i. CR) {. rest
    {. (nums_from_str line) , 0
  else.
    0
  end.
)

route_request =: 3 : 0
  'method path query body' =. y
  path =. , path
  if. method -: 'OPTIONS' do.
    ('204 No Content' ; 'text/plain') http_response ''
  elseif. (path -: ,'/') +. (path -: '/index.html') do.
    'text/html; charset=utf-8' serve_static '/index.html'
  elseif. path -: '/style.css' do.
    'text/css; charset=utf-8' serve_static '/style.css'
  elseif. path -: '/app.js' do.
    'application/javascript; charset=utf-8' serve_static '/app.js'
  elseif. path -: '/favicon.ico' do.
    ('200 OK' ; 'image/svg+xml') http_response FAVICON_SVG
  elseif. path -: '/api/state' do.
    ('200 OK' ; 'application/json; charset=utf-8') http_response sample_all_sensors ''
  elseif. path -: '/api/control' do.
    params =. body , (0 = #body) # query
    ('200 OK' ; 'application/json; charset=utf-8') http_response handle_control params
  elseif. path -: '/api/client-sensors' do.
    params =. body , (0 = #body) # query
    ('200 OK' ; 'application/json; charset=utf-8') http_response handle_client_sensors params
  elseif. path -: '/api/eval' do.
    params =. body , (0 = #body) # query
    expr =. 'expr' get_param params
    ('200 OK' ; 'application/json; charset=utf-8') http_response eval_j_expr expr
  elseif. 1 do.
    ('404 Not Found' ; 'application/json; charset=utf-8') http_response '{"status":"error","message":"Ruta no encontrada"}'
  end.
)

NB. Timeout corto (150ms) en lectura inicial para no bloquearse con sockets
NB. de pre-conexión especulativa de Chrome en Android (Google Pixel)
handle_client_socket =: 3 : 0
  sk =. y
  try.
    buf =. ''
    hdr_end =. _1
    while. hdr_end = _1 do.
      sel =. sdselect_jsocket_ sk ; '' ; '' ; 150
      if. -. sk e. > 1 { sel do. break. end.
      'rc chunk' =. sdrecv_jsocket_ sk , 16384 , 0
      if. (rc ~: 0) +. (0 = # chunk) do. break. end.
      buf =. buf , chunk
      idx =. ((CRLF , CRLF) E. buf) i. 1
      if. idx < # buf do. hdr_end =. idx end.
    end.
    if. hdr_end >: 0 do.
      hdr_str =. hdr_end {. buf
      body    =. (hdr_end + 4) }. buf
      clen    =. get_content_length hdr_str
      while. (# body) < clen do.
        sel =. sdselect_jsocket_ sk ; '' ; '' ; 500
        if. -. sk e. > 1 { sel do. break. end.
        'rc chunk' =. sdrecv_jsocket_ sk , 16384 , 0
        if. (rc ~: 0) +. (0 = # chunk) do. break. end.
        body =. body , chunk
      end.
      body =. clen {. body
      first_line =. (hdr_str i. CR) {. hdr_str
      parts =. <;._1 ' ' , first_line
      method =. > 0 { parts , <'GET'
      full_url =. > 1 { parts , <'/'
      qpos =. full_url i. '?'
      path =. qpos {. full_url
      query =. (>: qpos) }. full_url
      resp =. route_request method ; path ; query ; body
      while. # resp do.
        'rc sent' =. resp sdsend_jsocket_ sk , 0
        if. (rc ~: 0) +. (sent <: 0) do. break. end.
        resp =. sent }. resp
      end.
    end.
  catch.
    smoutput 'Aviso en socket HTTP: ' , 13!:12 ''
  end.
  shutdownJ_jsocket_ :: 0: sk ; 2
  sdclose_jsocket_ :: 0: sk
  i. 0 0
)

start_server =: 3 : 0
  if. # y do. PORT_HUB =: {. y end.
  sdcleanup_jsocket_ ''
  NB. Si el puerto solicitado está ocupado (ej. 8080 en Pixel VM), buscar el siguiente libre automáticamente
  bound =. 0
  tries =. 0
  while. (-. bound) *. (tries < 50) do.
    SK_SRV =: 0 pick sdcheck_jsocket_ sdsocket_jsocket_ ''
    sdsetsockopt_jsocket_ SK_SRV ; SOL_SOCKET_jsocket_ ; SO_REUSEADDR_jsocket_ ; 2-1
    r =. sdbind_jsocket_ SK_SRV ; AF_INET_jsocket_ ; '' ; PORT_HUB
    if. r = 0 do.
      bound =. 1
    else.
      smoutput 'Aviso: Puerto ' , (": PORT_HUB) , ' ocupado (' , (sderror_jsocket_ r) , '). Probando ' , (": >: PORT_HUB) , '...'
      sdclose_jsocket_ :: 0: SK_SRV
      PORT_HUB =: >: PORT_HUB
      tries =. >: tries
    end.
  end.
  if. -. bound do.
    smoutput 'Error: No se encontró un puerto libre.'
    exit 1
  end.
  sdcheck_jsocket_ sdlisten_jsocket_ SK_SRV , 32
  url =. 'http://localhost:' , ": PORT_HUB
  smoutput '==================================================================='
  smoutput ' J Sensor Hub (Jsoftware J9.7 ARM64) - Edición Google Pixel (droid)'
  smoutput ' -> Servidor ACTIVO y escuchando en 0.0.0.0:' , ": PORT_HUB
  smoutput ' -> Abre en Chrome de tu Pixel: ' , url
  smoutput ' -> IMPORTANTE en Google Pixel: En la barra superior de la app'
  smoutput '    Terminal de Android toca el icono de "Puertos" (Port forwarding)'
  smoutput '    y activa el interruptor del puerto ' , (": PORT_HUB) , '.'
  smoutput '==================================================================='
  NB. Si existe el socket url_forwarder del Pixel, enviar la URL al navegador de Android
  try.
    2!:0 :: 0: 'if [ -S /run/url_forwarder/url_forwarder.sock ]; then /usr/bin/url_forwarder_wrapper "' , url , '" >/dev/null 2>&1 & fi'
  catch. end.
  while. 1 do.
    try.
      sel =. sdselect_jsocket_ SK_SRV ; '' ; '' ; 2000
      if. SK_SRV e. > 1 { sel do.
        cli =. 0 pick sdcheck_jsocket_ sdaccept_jsocket_ SK_SRV
        handle_client_socket cli
      end.
    catch.
      smoutput 'Aviso en bucle de servidor: ' , 13!:12 ''
    end.
  end.
)
