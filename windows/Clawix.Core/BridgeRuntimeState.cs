namespace Clawix.Core;

public abstract record BridgeRuntimeState
{
    public abstract string WireTag { get; }

    public virtual string? ErrorMessage => null;

    public sealed record Booting : BridgeRuntimeState
    {
        public override string WireTag => "booting";
    }

    public sealed record Syncing : BridgeRuntimeState
    {
        public override string WireTag => "syncing";
    }

    public sealed record Ready : BridgeRuntimeState
    {
        public override string WireTag => "ready";
    }

    public sealed record Error(string Message) : BridgeRuntimeState
    {
        public override string WireTag => "error";

        public override string? ErrorMessage => Message;
    }
}
