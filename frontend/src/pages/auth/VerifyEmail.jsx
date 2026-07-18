import {
    useEffect,
    useState
}
    from "react";


import {
    useSearchParams
}
    from "react-router-dom";


import {
    verifyEmail
}
    from "../../api/auth.api";



function VerifyEmail() {


    const [params] = useSearchParams();


    const token =
        params.get("token");


    const [message, setMessage] = useState("");



    useEffect(() => {


        async function verify() {


            try {


                await verifyEmail({

                    token

                });


                setMessage(
                    "Email verified successfully"
                );


            }

            catch (error) {


                setMessage(
                    "Invalid verification token"
                );


            }


        }


        verify();


    }, []);




    return (

        <div className="auth-container">

            <div className="auth-card">

                <h2>
                    Email Verification
                </h2>


                <p>
                    {message}
                </p>


            </div>

        </div>

    );


}


export default VerifyEmail;