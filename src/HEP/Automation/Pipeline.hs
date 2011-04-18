module HEP.Automation.Pipeline where

import Control.Monad.Reader 

import HEP.Automation.MadGraph.Run
import HEP.Automation.MadGraph.Model
import HEP.Automation.MadGraph.SetupType
import HEP.Automation.MadGraph.Util


import System.Posix.Unistd (sleep)
import System.FilePath ((</>))
import System.Directory

import Text.Parsec 

import HEP.Storage.WebDAV

import HEP.Automation.Pipeline.Config 
import HEP.Automation.Pipeline.DetectorAnalysis
import HEP.Automation.Pipeline.EventGeneration
import HEP.Automation.Pipeline.TopAFB


import HEP.Automation.Pipeline.Download

import Paths_pipeline

import qualified Data.ByteString.Lazy.Char8 as B 
import qualified Data.Binary as Bi
import qualified Data.Binary.Get as G
-- import qualified Data.ListLike as LL 
import qualified Data.Iteratee as Iter 

pipelineTopAFB :: (Model a) => 
                  String   -- ^ system config
                  -> String -- ^ user config 
                  -> (ScriptSetup -> ClusterSetup -> [WorkSetup a] ) 
                     -- ^ tasklistf 
                  -> WebDAVConfig
                  -> AnalysisWorkConfig 
                  -> IO () 
pipelineTopAFB confsys confusr tasklistf wdav aconf = do 
  confresult <- parseConfig confsys confusr
  case confresult of 
    Left errormsg -> do 
      putStrLn errormsg
    Right (ssetup,csetup) -> do 
      putStrLn "top afb" 
      let tasklist = tasklistf ssetup csetup 
          wdir = anal_workdir aconf 
      templdir <- return . ( </> "template" ) =<< getDataDir 
      forM_ tasklist $
        \x -> do 
          download_PartonLHEGZ wdav wdir x 
          download_BannerTXT wdav wdir x 
          let rname = makeRunName (ws_psetup x) (ws_rsetup x)
              lhefilename = rname ++ "_unweighted_events.lhe.gz"
              bannerfilename = rname ++ "_banner.txt"
              exportfilenameTopInfo = rname ++ "_topinfo.dat"
              exportfilenameSuccintInfo = rname ++ "_succintinfo.dat"
              afb = TopAFBSetup {
                        afb_mainpkgfile = "mainTopInfoRoutine.m"
                      , afb_topinfoexportpkgfile = "topInfoExport.m"
                      , afb_lhefile = lhefilename
                      , afb_bannerfile = bannerfilename
                      , afb_exportfileTopInfo = exportfilenameTopInfo 
                      , afb_exportfileSuccintInfo = exportfilenameSuccintInfo
                      }
          topAFBSetup afb templdir wdir 
          topAFBRunMathematica afb wdir 

pipelineLHCOAnal :: (Model a) => 
                  String              -- ^ system config  
                  -> String           -- ^ user config
                  -> ( ScriptSetup -> ClusterSetup -> [WorkSetup a] )  
                      -- ^ tasklist 
                  -> WebDAVConfig
                  -> WebDAVRemoteDir
                  -> AnalysisWorkConfig 
                  -> IO ()
pipelineLHCOAnal confsys confusr tasklistf wdav rdir aconf = do 
  confresult <- parseConfig confsys confusr
  case confresult of 
    Left errormsg -> do 
      putStrLn errormsg
    Right (ssetup,csetup) -> do 
      putStrLn "LHCAnalysis" 
      let tasklist = tasklistf ssetup csetup 
          wdir = anal_workdir aconf 
      forM_ tasklist $ 
        \x -> do 
          download_LHCO wdav wdir x 
          xformLHCOtoBinary wdir x
          lst <- makePhyEventClassifiedList wdir x 
          r <- eventFeedToIteratee lst testcount 
--               Iter.length `Iter.enumPair` iter_count_marker1000 
          putStrLn $ show r
          
          


pipelineEvGen  :: (Model a) => 
                  String              -- ^ system config  
                  -> String           -- ^ user config
                  -> EventGenerationSwitch 
                  -> (EventGenerationSwitch -> WorkIO a ())      -- ^ command
                  -> [ProcessSetup a] -- ^ process setup list 
                  -> ( ScriptSetup -> ClusterSetup -> [WorkSetup a] )  
                      -- ^ tasklist gen function 
                  -> IO ()
pipelineEvGen confsys confusr egs command psetuplist tasklistf = do 
  confresult <- parseConfig confsys confusr
  case confresult of 
    Left errormsg -> do 
      putStrLn errormsg
    Right (ssetup,csetup) -> do 
      -- create working directory (only once for each process)

--      putStrLn . show $ tasklistf ssetup csetup 
      case dirGenSwitch egs of 
        True -> mapM_ (createWorkDir ssetup) psetuplist
        False -> return ()
      sleep 2
      mapM_ (runReaderT (command egs)) (tasklistf ssetup csetup)

       

          