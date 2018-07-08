import org.eclipse.ceylon.model.typechecker.model {
    SiteVariance
}

class Variance {
    shared SiteVariance? siteVariance;

    shared new covariant {
        this.siteVariance = SiteVariance.\iOUT;
    }

    shared new contravariant {
        this.siteVariance = SiteVariance.\iIN;
    }

    shared new invariant {
        this.siteVariance = null;
    }
}
