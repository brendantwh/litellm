from typing import Optional, Union
import os

import httpx

# Try to import httpx-curl-cffi transport
try:
    from httpx_curl_cffi import AsyncCurlTransport, CurlOpt
    CURL_CFFI_AVAILABLE = True
except ImportError:
    CURL_CFFI_AVAILABLE = False
    AsyncCurlTransport = None
    CurlOpt = None

try:
    from litellm._version import version
except Exception:
    version = "0.0.0"

headers = {
    "User-Agent": f"litellm/{version}",
}


def _should_use_curl_cffi() -> bool:
    """
    Check if curl_cffi transport should be used.
    
    Controlled by:
        - Environment variable: LITELLM_USE_CURL_CFFI=true
        - Or litellm.use_curl_cffi = True
    
    Default: False (use standard httpx)
    """
    if not CURL_CFFI_AVAILABLE:
        return False
    
    # Check environment variable first
    use_curl_cffi = os.getenv("LITELLM_USE_CURL_CFFI", "false").lower()
    if use_curl_cffi in ("true", "1", "yes"):
        return True
    
    # Check litellm module variable
    try:
        import litellm
        if hasattr(litellm, "use_curl_cffi") and litellm.use_curl_cffi is True:
            return True
    except Exception:
        pass
    
    return False


class HTTPHandler:
    def __init__(
        self, 
        concurrent_limit=1000, 
        timeout: Optional[Union[float, httpx.Timeout]] = None,
        use_curl_cffi: Optional[bool] = None
    ):
        """
        Initialize HTTPHandler with optional curl_cffi transport.
        
        Args:
            concurrent_limit: Maximum number of concurrent connections
            timeout: Timeout for requests (float or httpx.Timeout object)
            use_curl_cffi: Override environment variable to force curl_cffi usage.
                          If None, uses LITELLM_USE_CURL_CFFI env var or litellm.use_curl_cffi.
        """
        # Determine whether to use curl_cffi
        if use_curl_cffi is None:
            use_curl_cffi = _should_use_curl_cffi()
        
        # Create a client with appropriate transport
        if use_curl_cffi and CURL_CFFI_AVAILABLE:
            # Use curl_cffi transport for better performance and bot detection evasion
            transport = AsyncCurlTransport(  # type: ignore
                max_connections=concurrent_limit,
                # Required for parallel requests - see https://github.com/lexiforest/curl_cffi/issues/302
                curl_options={CurlOpt.FRESH_CONNECT: True},  # type: ignore
            )
            self.client = httpx.AsyncClient(
                transport=transport,
                headers=headers,
                timeout=timeout,
            )
            self.using_curl_cffi = True
        else:
            # Standard httpx implementation
            self.client = httpx.AsyncClient(
                limits=httpx.Limits(
                    max_connections=concurrent_limit,
                    max_keepalive_connections=concurrent_limit,
                ),
                headers=headers,
                timeout=timeout,
            )
            self.using_curl_cffi = False

    async def close(self):
        # Close the client when you're done with it
        await self.client.aclose()

    async def get(
        self, url: str, params: Optional[dict] = None, headers: Optional[dict] = None
    ):
        response = await self.client.get(url, params=params, headers=headers)
        return response

    async def post(
        self,
        url: str,
        data: Optional[Union[dict, str]] = None,
        params: Optional[dict] = None,
        headers: Optional[dict] = None,
    ):
        try:
            response = await self.client.post(
                url, data=data, params=params, headers=headers  # type: ignore
            )
            return response
        except Exception as e:
            raise e
