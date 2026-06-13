using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CitizenFX.Core;
using CitizenFX.Core.Native;

namespace bcrypt.Server
{
    public class ServerMain : BaseScript
    {
        Dictionary<int, string> pendingResolves = new Dictionary<int, string>();
        string curResourceName;

        public ServerMain()
        {
            curResourceName = API.GetCurrentResourceName();
            Tick += ServerMain_Tick;
            EventHandlers.Add("bcrypt:GetPasswordHash", new Action<int, string>(GetPasswordHash));
            EventHandlers.Add("bcrypt:VerifyPasswordHash", new Action<int, string, string>(VerifyPasswordHash));
        }

        private Task ServerMain_Tick()
        {
            foreach (KeyValuePair<int, string> kvp in pendingResolves)
            {
                TriggerEvent("bcrypt:resolve", kvp.Key, kvp.Value);
            }
            pendingResolves.Clear();
            return Task.CompletedTask;
        }

        public void GetPasswordHash(int promiseId, string plainText)
        {
            if (API.GetInvokingResource() != curResourceName)
            {
                Debug.WriteLine("This event should only be called internally by the bcrypt resource.");
                pendingResolves.Add(promiseId, "");
                return;
            }
            new Thread(() =>
            {
                string hash = API.GetPasswordHash(plainText);
                pendingResolves.Add(promiseId, hash);
            }).Start();
        }

        public void VerifyPasswordHash(int promiseId, string plainText, string hash)
        {
            if (API.GetInvokingResource() != curResourceName)
            {
                Debug.WriteLine("This event should only be called internally by the bcrypt resource.");
                pendingResolves.Add(promiseId, "");
                return;
            }
            new Thread(() =>
            {
                bool success = API.VerifyPasswordHash(plainText, hash);
                pendingResolves.Add(promiseId, success.ToString());
            }).Start();
        }
    }
}