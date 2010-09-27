module Happstack.Server.Proxy where

import Control.Monad                             (MonadPlus(mzero))
import Control.Monad.Trans                       (MonadIO(liftIO))
import Data.List                                 (isPrefixOf)
import Happstack.Server.Monads                   (ServerMonad(askRq), FilterMonad, WebMonad, escape')
import Happstack.Server.Response                 (badGateway, toResponse)
import Happstack.Server.HTTP.Client              (getResponse, unproxify, unrproxify)
import Happstack.Server.HTTP.Types               (Request(rqPaths), Response)

-- | The 'proxyServe' is for creating 'ServerPartT's that proxy.  The
-- sole argument @['String']@ is a list of allowed domains for
-- proxying.  This matches the domain part of the request and the
-- wildcard * can be used. E.g.
--
--  * \"*\" to match anything.
--
--  * \"*.example.com\" to match anything under example.com
--
--  * \"example.com\" to match just example.com
--
--
--  TODO: annoyingly enough, this method eventually calls 'escape', so
--  any headers you set won't be used, and the computation immediately
--  ends.
proxyServe :: (MonadIO m, WebMonad Response m, ServerMonad m, MonadPlus m, FilterMonad Response m) => [String] -> m Response
proxyServe allowed = do
   rq <- askRq
   if cond rq then proxyServe' rq else mzero
   where
   cond rq
     | "*" `elem` allowed = True
     | domain `elem` allowed = True
     | superdomain `elem` wildcards =True
     | otherwise = False
     where
     domain = head (rqPaths rq)
     superdomain = tail $ snd $ break (=='.') domain
     wildcards = (map (drop 2) $ filter ("*." `isPrefixOf`) allowed)

-- | Take a proxy 'Request' and create a 'Response'.  Your basic proxy
-- building block.  See 'unproxify'.
--
-- TODO: this would be more useful if it didn\'t call 'escape'
-- (e.g. it let you modify the response afterwards, or set additional
-- headers)
proxyServe' :: (MonadIO m, FilterMonad Response m, WebMonad Response m) => Request-> m Response
proxyServe' rq = liftIO (getResponse (unproxify rq)) >>=
                either (badGateway . toResponse . show) escape'

-- | This is a reverse proxy implementation.  See 'unrproxify'.
--
-- TODO: this would be more useful if it didn\'t call 'escape', just
-- like 'proxyServe''.
rproxyServe :: (ServerMonad m, WebMonad Response m, FilterMonad Response m, MonadIO m) =>
    String -- ^ defaultHost
    -> [(String, String)] -- ^ map to look up hostname mappings.  For the reverse proxy
    -> m Response -- ^ the result is a 'ServerPartT' that will reverse proxy for you.
rproxyServe defaultHost list  = 
    do rq <- askRq
       r <- liftIO (getResponse (unrproxify defaultHost list rq))
       either (badGateway . toResponse . show) (escape') r
