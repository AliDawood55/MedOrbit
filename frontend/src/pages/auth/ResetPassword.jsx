import { useState } from "react";

import {
    useSearchParams,
    useNavigate
}
    from "react-router-dom";


import {
    resetPassword
}
    from "../../api/auth.api";



function ResetPassword() {


    const [searchParams] = useSearchParams();


    const navigate = useNavigate();


    const token =
        searchParams.get("token");


    const [password, setPassword] = useState("");

    const [message, setMessage] = useState("");



    async function submit(e) {

        e.preventDefault();


        try {


            await resetPassword({

                token,

                newPassword: password

            });


            setMessage(
                "Password changed successfully"
            );


            setTimeout(() => {

                navigate("/login");

            }, 2000);



        }
        catch (error) {


            setMessage(
                error.response?.data?.error?.message ||
                "Invalid token"
            );


        }


    }



    return (

        <div className="auth-container">


            <div className="auth-card">


                <h2>
                    Reset Password
                </h2>


                <form onSubmit={submit}>


                    <input

                        type="password"

                        placeholder="New Password"

                        value={password}

                        onChange={
                            e => setPassword(e.target.value)
                        }

                    />


                    <button>

                        Change Password

                    </button>


                </form>


                <p>
                    {message}
                </p>


            </div>


        </div>


    );


}


export default ResetPassword;