{-# LANGUAGE OverloadedStrings #-}

module Lib (embeder) where

import Data.Composition
import Data.Text (Text)
import Data.Text.IO as TIO
import UnliftIO

import Discord
import Discord.Interactions
import Discord.Requests
import Discord.Types

import Commands as C
import Helper
import Joint ((<.>))
import State

embeder :: Text -> IO ()
embeder token =
  loadState
    >>= ( \state ->
            runDiscord
              ( def
                  { discordToken = token
                  , discordOnStart = onStart
                  , -- FIXME: does not save state but instead an empty map
                    discordOnEnd = saveState state *> TIO.putStrLn "Saved State"
                  , discordOnEvent = eventHandler state
                  , discordOnLog = TIO.putStrLn
                  , discordGatewayIntent =
                      GatewayIntent
                        { gatewayIntentGuilds = True
                        , gatewayIntentMembers = False
                        , gatewayIntentBans = False
                        , gatewayIntentEmojis = False
                        , gatewayIntentIntegrations = False
                        , gatewayIntentWebhooks = False
                        , gatewayIntentInvites = False
                        , gatewayIntentVoiceStates = False
                        , gatewayIntentPresences = False
                        , gatewayIntentMessageChanges = False
                        , gatewayIntentMessageReactions = False
                        , gatewayIntentMessageTyping = False
                        , gatewayIntentDirectMessageChanges = False
                        , gatewayIntentDirectMessageReactions = False
                        , gatewayIntentDirectMessageTyping = False
                        , gatewayIntentMessageContent = False
                        }
                  }
              )
        )
    >>= TIO.putStrLn

eventHandler :: MVar State -> Event -> DiscordHandler ()
eventHandler _ (Ready{}) = writeLog "Ready"
eventHandler _ (GuildCreate _ _) = pure ()
eventHandler
  state
  ( InteractionCreate
      ( InteractionApplicationCommand
          { interactionId = iId
          , interactionToken = iToken
          , applicationCommandData = cData
          , interactionUser = MemberOrUser iUser
          }
        )
    ) =
    case (uId', cData) of
      (Just uId, ApplicationCommandDataMessage _ "As Template" resolved message) -> handleChatInput' uId $ C.saveTemplate resolved message
      (Just uId, ApplicationCommandDataChatInput _ "spawn" resolved options) -> handleChatInput' uId $ C.spawn resolved options
      (Just uId, ApplicationCommandDataChatInput _ "set" resolved options) -> handleChatInput' uId $ C.set resolved options
      _ -> missingImplementationResponse iId iToken ()
   where
    uId' = either (userId <.> memberUser) (pure . userId) iUser
    handleChatInput' = handleChatInput state iId iToken
eventHandler _ _ = pure ()

onStart :: DiscordHandler ()
onStart = handleRestCallError setupCommands *> setupActivity
 where
  applicationId = fullApplicationID <$> restCall' GetCurrentApplication
  setupCommands =
    applicationId
      >>= ( restCall' .: flip BulkOverWriteGlobalApplicationCommand $
              [ CreateApplicationCommandMessage
                  { createName = "As Template"
                  , createLocalizedName = Nothing
                  , createDefaultMemberPermissions = Nothing
                  , createDMPermission = Just True
                  }
              , CreateApplicationCommandChatInput
                  { createName = "spawn"
                  , createLocalizedName = Nothing
                  , createDescription = "Instanciate an embed template"
                  , createLocalizedDescription = Nothing
                  , createOptions =
                      Just . OptionsValues $
                        [ OptionValueString "name" Nothing "The name of the template" Nothing True (Left True) (Just 1) Nothing
                        , OptionValueString "id" Nothing "Id of the instance" Nothing True (Left True) (Just 1) Nothing
                        ]
                  , createDefaultMemberPermissions = Nothing
                  , createDMPermission = Just True
                  }
              , CreateApplicationCommandChatInput
                  { createName = "set"
                  , createLocalizedName = Nothing
                  , createDescription = "Set fields of an embed"
                  , createLocalizedDescription = Nothing
                  , createOptions =
                      Just . OptionsValues $
                        [ OptionValueString "id" Nothing "Id of the instance" Nothing True (Left True) (Just 1) Nothing
                        , OptionValueString "changes" Nothing "Of the format: `[+]<key>=<value>|-<key>`" Nothing True (Left True) (Just 1) Nothing
                        ]
                  , createDefaultMemberPermissions = Nothing
                  , createDMPermission = Just True
                  }
              ]
          )
  setupActivity =
    sendCommand . UpdateStatus $
      UpdateStatusOpts
        Nothing
        []
        UpdateStatusDoNotDisturb
        False
