-- Setup Push Subscription from Publisher to Subscriber
-- Run this on the Publisher after both instances are configured
-- This is an alternative to pull subscription

USE ReplicationDemo;
GO

-- Add the subscriber to the publisher
EXEC sp_addsubscriber 
    @subscriber = N'sqlserver-subscriber',
    @type = 0,
    @login = N'sa',
    @password = N'YourStrong!Passw0rd',
    @commit = 1,
    @description = N'Subscriber server for ReplicationDemo',
    @security_mode = 0;
GO

-- Add push subscription
EXEC sp_addsubscription 
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @destination_db = N'ReplicationDemo',
    @subscription_type = N'push',
    @sync_type = N'automatic',
    @article = N'all',
    @update_mode = N'read only',
    @subscriber_type = 0;
GO

-- Add the distribution agent for the push subscription
EXEC sp_addpushsubscription_agent 
    @publication = N'ReplicationDemo_Publication',
    @subscriber = N'sqlserver-subscriber',
    @subscriber_db = N'ReplicationDemo',
    @subscriber_security_mode = 0,
    @subscriber_login = N'sa',
    @subscriber_password = N'YourStrong!Passw0rd',
    @distributor_security_mode = 1,
    @frequency_type = 64,
    @frequency_interval = 1,
    @frequency_relative_interval = 1,
    @frequency_recurrence_factor = 0,
    @frequency_subday = 4,
    @frequency_subday_interval = 5,
    @active_start_time_of_day = 0,
    @active_end_time_of_day = 235959,
    @active_start_date = 0,
    @active_end_date = 0,
    @enabled_for_syncmgr = N'False',
    @dts_package_location = N'Distributor';
GO

PRINT 'Push subscription configured successfully';
GO
